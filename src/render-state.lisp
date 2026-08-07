;;;; src/render-state.lisp -- renderer state and snapshot preparation.
(in-package #:cl-asciiquarium)

(defstruct (%creature-render-snapshot
            (:constructor
             %make-creature-render-snapshot
             (x y width height runs frame-index facing z))) x
  y
  width
  height
  runs
  frame-index
  facing
  z
  (seen-generation 0))

(defstruct (%dirty-rectangles
            (:constructor %make-dirty-rectangles (&optional (capacity 16))))
  (data (make-array capacity :element-type 'fixnum))
  (count 0 :type fixnum))

(defstruct (%renderer-frame-state
            (:constructor
             %make-renderer-frame-state
             (width height snapshots render-order dirty-rectangles generation
              last-world-tick)))
  width
  height
  snapshots
  render-order
  dirty-rectangles
  generation
  last-world-tick
  executor
  parallel-creatures
  parallel-input-snapshots
  parallel-results
  parallel-promises
  parallel-cache-hot-p)

(defstruct (%render-preparation-result
            (:constructor %make-render-preparation-result ()))
  current-p
  snapshot
  x
  y
  width
  height
  runs
  frame-index
  facing
  z
  cache-rebuilt-p)

;; A weak key prevents renderer-specific snapshots from retaining a renderer.
(defvar *renderer-frame-states* (make-hash-table :test #'eq :weakness :key))

;; Renderer state and its reusable executor form one lifecycle unit. The project
;; is SBCL-only, so a mutex gives render and shutdown a precise ownership edge.
(defvar *renderer-ownership-lock*
  (sb-thread:make-mutex :name "cl-asciiquarium-renderer-ownership"))

;; The clipped-blit fast path makes work proportional to dirty area, rather
;; than to the number of changed creatures. Recompose locally until the
;; rectangles cover at least half the screen; after that, clearing and painting
;; once is cheaper and bounds the worst case.
(defconstant +render-frame-full-redraw-area-denominator+ 2)

(defconstant +render-frame-full-redraw-rectangle-denominator+ 4)

;; Snapshot validation is independent per creature, but submitting tiny worlds
;; costs more than it saves. Keep the executor fixed and use a bounded number
;; of chunks so task overhead stays below the rendering work.
(defconstant +render-frame-parallel-minimum-creatures+ 64)
(defconstant +render-frame-parallel-minimum-cache-rebuilds+ 16)
(defconstant +render-frame-parallel-worker-count+ 4)

(defun %ensure-render-parallel-vector (vector size)
  (cond
    ((null vector) (make-array size :initial-element nil))
    ((>= (length vector) size) vector)
    (t (adjust-array vector size :initial-element nil))))

(defun %ensure-render-parallel-state (state count)
  (unless (%renderer-frame-state-executor state)
    (setf (%renderer-frame-state-executor state)
          (make-executor
           :size +render-frame-parallel-worker-count+
           :name "cl-asciiquarium-render"
           :queue-capacity +render-frame-parallel-worker-count+)))
  (setf (%renderer-frame-state-parallel-creatures state)
        (%ensure-render-parallel-vector
         (%renderer-frame-state-parallel-creatures state)
         count)
        (%renderer-frame-state-parallel-input-snapshots state)
        (%ensure-render-parallel-vector
         (%renderer-frame-state-parallel-input-snapshots state)
         count)
        (%renderer-frame-state-parallel-results state)
        (%ensure-render-parallel-vector
         (%renderer-frame-state-parallel-results state)
         count)
        (%renderer-frame-state-parallel-promises state)
        (%ensure-render-parallel-vector
         (%renderer-frame-state-parallel-promises state)
         +render-frame-parallel-worker-count+))
  (let ((results (%renderer-frame-state-parallel-results state)))
    (dotimes (index count)
      (unless (aref results index)
        (setf (aref results index) (%make-render-preparation-result)))))
  state)

(defun %add-dirty-rectangle (rectangles left top right bottom)
  "Add a rectangle, coalescing all touching regions in the reusable buffer."
  (let ((index 0)
        (count (%dirty-rectangles-count rectangles))
        (data (%dirty-rectangles-data rectangles)))
    (loop while (< index count)
          for offset = (* index 4)
          for existing-left = (aref data offset)
          for existing-top = (aref data (1+ offset))
          for existing-right = (+ existing-left (aref data (+ offset 2)))
          for existing-bottom = (+ existing-top (aref data (+ offset 3)))
          do (if (and (<= left existing-right)
                      (<= existing-left right)
                      (<= top existing-bottom)
                      (<= existing-top bottom))
                 (progn
                   (setf left (min left existing-left)
                         top (min top existing-top)
                         right (max right existing-right)
                         bottom (max bottom existing-bottom))
                   (decf count)
                   (when (< index count)
                     (let ((last-offset (* count 4)))
                       (setf (aref data offset) (aref data last-offset)
                             (aref data (1+ offset)) (aref data (1+ last-offset))
                             (aref data (+ offset 2)) (aref data (+ last-offset 2))
                             (aref data (+ offset 3)) (aref data (+ last-offset 3)))))
                   (setf index 0))
                 (incf index)))
    (when (> (* 4 (1+ count)) (length data))
      (setf data (adjust-array data (* 2 (length data)))
            (%dirty-rectangles-data rectangles) data))
    (let ((offset (* count 4)))
      (setf (aref data offset) left
            (aref data (1+ offset)) top
            (aref data (+ offset 2)) (- right left)
            (aref data (+ offset 3)) (- bottom top)
            (%dirty-rectangles-count rectangles) (1+ count)))
    rectangles))

(defun %add-clipped-dirty-rectangle (rectangles snapshot screen-width screen-height)
  (let* ((left (max 0 (%creature-render-snapshot-x snapshot)))
         (top (max 0 (%creature-render-snapshot-y snapshot)))
         (right (min screen-width
                     (+ (%creature-render-snapshot-x snapshot)
                        (%creature-render-snapshot-width snapshot))))
         (bottom (min screen-height
                      (+ (%creature-render-snapshot-y snapshot)
                         (%creature-render-snapshot-height snapshot)))))
    (if (and (< left right) (< top bottom))
        (%add-dirty-rectangle rectangles left top right bottom)
        rectangles)))

(defun %dirty-rectangles-cover-half-screen-p (rectangles screen-width screen-height)
  (let ((data (%dirty-rectangles-data rectangles)))
    (>= (* +render-frame-full-redraw-area-denominator+
           (loop for index below (%dirty-rectangles-count rectangles)
                 for offset = (* index 4)
                 sum (* (aref data (+ offset 2)) (aref data (+ offset 3)))))
        (* screen-width screen-height))))

(defun %dirty-rectangles-exceed-render-budget-p (rectangles render-order)
  "Whether local layer checks cost more than a single full repaint."
  (let ((rectangle-count (%dirty-rectangles-count rectangles))
        (creature-count (length render-order)))
    (and (> rectangle-count 1)
         (plusp creature-count)
         (>= (* +render-frame-full-redraw-rectangle-denominator+ rectangle-count)
             creature-count))))

(defun %snapshot-creature-for-rendering (creature)
  (multiple-value-bind (ignored cache-rebuilt-p)
      (%ensure-creature-caches-current creature)
    (declare (ignore ignored))
    (multiple-value-bind (x y width height) (creature-bounds creature)
      (let ((frame-index (creature-frame-index creature))
            (facing (creature-facing creature)))
        (values
         (%make-creature-render-snapshot
          x
          y
          width
          height
          (if (eq facing :left) (aref
                                 (creature-%mirrored-frame-runs creature)
                                 frame-index)
            (aref (creature-%frame-runs creature) frame-index))
          frame-index
          facing
          (creature-z creature))
         cache-rebuilt-p)))))

(defun %creature-render-snapshot-current-p (snapshot creature)
  (multiple-value-bind (ignored cache-rebuilt-p)
      (%ensure-creature-caches-current creature)
    (declare (ignore ignored))
    (multiple-value-bind (x y width height) (%creature-bounds-current creature)
      (let* ((frame-index (creature-frame-index creature))
             (facing (creature-facing creature))
             (runs
              (if (eq facing :left) (aref
                                     (creature-%mirrored-frame-runs creature)
                                     frame-index)
                (aref (creature-%frame-runs creature) frame-index)))
             (z (creature-z creature)))
        (values
         (and
          (= (%creature-render-snapshot-x snapshot) x)
          (= (%creature-render-snapshot-y snapshot) y)
          (= (%creature-render-snapshot-width snapshot) width)
          (= (%creature-render-snapshot-height snapshot) height)
          (eq (%creature-render-snapshot-runs snapshot) runs)
          (= (%creature-render-snapshot-frame-index snapshot) frame-index)
          (eq (%creature-render-snapshot-facing snapshot) facing)
          (= (%creature-render-snapshot-z snapshot) z))
         x
         y
         width
         height
         runs
         frame-index
         facing
         z
         cache-rebuilt-p)))))

(defun %prepare-render-result (result snapshot creature)
  (if snapshot
      (multiple-value-bind
            (current-p x y width height runs frame-index facing z cache-rebuilt-p)
          (%creature-render-snapshot-current-p snapshot creature)
        (setf (%render-preparation-result-current-p result) current-p
              (%render-preparation-result-snapshot result) snapshot
              (%render-preparation-result-x result) x
              (%render-preparation-result-y result) y
              (%render-preparation-result-width result) width
              (%render-preparation-result-height result) height
              (%render-preparation-result-runs result) runs
              (%render-preparation-result-frame-index result) frame-index
              (%render-preparation-result-facing result) facing
              (%render-preparation-result-z result) z
              (%render-preparation-result-cache-rebuilt-p result)
              cache-rebuilt-p))
      (multiple-value-bind (new-snapshot cache-rebuilt-p)
          (%snapshot-creature-for-rendering creature)
        (setf (%render-preparation-result-current-p result) nil
              (%render-preparation-result-snapshot result) new-snapshot
              (%render-preparation-result-x result)
              (%creature-render-snapshot-x new-snapshot)
              (%render-preparation-result-y result)
              (%creature-render-snapshot-y new-snapshot)
              (%render-preparation-result-width result)
              (%creature-render-snapshot-width new-snapshot)
              (%render-preparation-result-height result)
              (%creature-render-snapshot-height new-snapshot)
              (%render-preparation-result-runs result)
              (%creature-render-snapshot-runs new-snapshot)
              (%render-preparation-result-frame-index result)
              (%creature-render-snapshot-frame-index new-snapshot)
              (%render-preparation-result-facing result)
              (%creature-render-snapshot-facing new-snapshot)
              (%render-preparation-result-z result)
              (%creature-render-snapshot-z new-snapshot)
              (%render-preparation-result-cache-rebuilt-p result)
              cache-rebuilt-p)))
  result)

(defun %prepare-render-snapshots-parallel (state render-order snapshots)
  (let* ((count (length render-order))
         (worker-count (min +render-frame-parallel-worker-count+ count)))
    (%ensure-render-parallel-state state count)
    (let ((creatures (%renderer-frame-state-parallel-creatures state))
          (input-snapshots
            (%renderer-frame-state-parallel-input-snapshots state))
          (results (%renderer-frame-state-parallel-results state))
          (promises (%renderer-frame-state-parallel-promises state))
          (executor (%renderer-frame-state-executor state)))
      (loop for creature in render-order
            for index from 0
            do (setf (aref creatures index) creature
                     (aref input-snapshots index) (gethash creature snapshots)))
      (dotimes (worker worker-count)
        (let ((start (floor (* worker count) worker-count))
              (end (floor (* (1+ worker) count) worker-count)))
          (setf (aref promises worker)
                (submit
                 executor
                 (lambda ()
                   (loop for index from start below end
                         do (%prepare-render-result
                             (aref results index)
                             (aref input-snapshots index)
                             (aref creatures index)))
                   t)))))
      ;; Await every submitted chunk before propagating the first error. This
      ;; leaves no worker touching the reusable buffers when the caller resumes.
      (let ((first-error nil))
        (dotimes (worker worker-count)
          (handler-case
              (await (aref promises worker))
            (error (condition)
              (unless first-error
                (setf first-error condition)))))
        (when first-error
          (error first-error))))))

(defun %apply-render-preparation
    (creature result snapshots rectangles screen-width screen-height generation)
  "Reconcile RESULT with SNAPSHOTS and mark its changed screen regions."
  (let* ((snapshot (%render-preparation-result-snapshot result))
         (previous-snapshot (gethash creature snapshots)))
    (if previous-snapshot
        (unless (%render-preparation-result-current-p result)
          ;; Mark the old bounds before replacing the reusable snapshot fields.
          (%add-clipped-dirty-rectangle rectangles previous-snapshot
                                         screen-width screen-height)
          (setf (%creature-render-snapshot-x snapshot)
                (%render-preparation-result-x result)
                (%creature-render-snapshot-y snapshot)
                (%render-preparation-result-y result)
                (%creature-render-snapshot-width snapshot)
                (%render-preparation-result-width result)
                (%creature-render-snapshot-height snapshot)
                (%render-preparation-result-height result)
                (%creature-render-snapshot-runs snapshot)
                (%render-preparation-result-runs result)
                (%creature-render-snapshot-frame-index snapshot)
                (%render-preparation-result-frame-index result)
                (%creature-render-snapshot-facing snapshot)
                (%render-preparation-result-facing result)
                (%creature-render-snapshot-z snapshot)
                (%render-preparation-result-z result))
          (%add-clipped-dirty-rectangle rectangles snapshot
                                         screen-width screen-height))
        (setf (gethash creature snapshots) snapshot))
    (setf (%creature-render-snapshot-seen-generation snapshot) generation)
    (%render-preparation-result-cache-rebuilt-p result)))

(defun %shutdown-renderer-frame-state (state)
  (let ((executor (%renderer-frame-state-executor state)))
    (when executor
      (shutdown-executor executor :wait t)
      (await-executor-termination executor)
      (setf (%renderer-frame-state-executor state) nil)))
  state)

(defun shutdown-renderer (renderer)
  "Stop the reusable render executor owned by RENDERER, if any."
  (sb-thread:with-mutex (*renderer-ownership-lock*)
    (let ((state (gethash renderer *renderer-frame-states*)))
      (when state
        (%shutdown-renderer-frame-state state)
        (remhash renderer *renderer-frame-states*))))
  renderer)
