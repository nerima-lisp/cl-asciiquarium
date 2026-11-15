;;;; src/art-fisher.lisp -- the fisher event: a boat (kind :FISHER) that
;;;; arrives from an edge, a fishing line (:LINE) and hook (:HOOK) it lowers,
;;;; and the `!' (:CHEER) shown after a catch. The factory builds all four up
;;;; front, the line with one frame per length, so FISHER-TICK
;;;; (update-fisher.lisp) only adds them to the world and moves them. The line,
;;;; hook, and cheer share sprite prototypes, so neither a spawn nor a theme
;;;; change rebuilds their runs.
(in-package #:cl-asciiquarium)

(defun %fisher-boat-colors (theme)
  (values (mask-role-styles +fisher-colors+ :theme theme)
          (color-style :fg :theme theme)))

(defun fishing-line-frames (max-depth)
  "Return one line frame per length from 1 to MAX-DEPTH rows."
  (loop for length from 1 to max-depth
        collect (format nil "~{~A~^~%~}"
                        (make-list length :initial-element +fishing-line-glyph+))))

(defparameter +fisher-part-colors+ '((:line . :muted) (:hook . :fg) (:cheer . :live))
  "The theme color role each fisher part is drawn in.")

(defvar *fisher-part-prototypes* (make-hash-table :test #'equal)
  "Hook and cheer sprite prototypes keyed by (KIND THEME COLOR-MODE ASCII).")

(defvar *fishing-line-prototypes* (make-hash-table :test #'equal)
  "Line sprite prototypes of *FISHING-LINE-DEPTH* frames only, keyed by (THEME
COLOR-MODE ASCII). A line of another length empties it first, so the lines of
earlier screen heights are not kept.")

(defvar *fishing-line-depth* nil
  "The MAX-DEPTH every prototype in *FISHING-LINE-PROTOTYPES* was built for.")

(defun %fisher-part-table (kind max-depth)
  (cond ((not (eq kind :line)) *fisher-part-prototypes*)
        ((eql max-depth *fishing-line-depth*) *fishing-line-prototypes*)
        (t (setf *fishing-line-depth* max-depth)
           (clrhash *fishing-line-prototypes*))))

(defun %fisher-part-prototype (kind max-depth theme)
  (let ((table (%fisher-part-table kind max-depth))
        (key (list kind theme (effective-color-mode) *ascii*)))
    (or (gethash key table)
        (setf (gethash key table)
              (make-creature :kind :fisher-part-prototype
                             :frames (ecase kind
                                       (:line (fishing-line-frames max-depth))
                                       (:hook (list +fishing-hook-art+))
                                       (:cheer (list +fisher-cheer-art+)))
                             :style (color-style (cdr (assoc kind +fisher-part-colors+))
                                                 :theme theme)
                             :%trusted-frames-p t :%trusted-style-p t
                             :x 0 :y 0 :policy :none)))))

(defun %fisher-part-max-depth (kind boat)
  (and (eq kind :line) (getf (creature-data boat) :max-depth)))

(defun %make-fisher-part (world kind boat &key tick place ttl threat)
  (make-creature :world world :kind kind
                 :%sprite-prototype (%fisher-part-prototype
                                     kind (%fisher-part-max-depth kind boat) (world-theme world))
                 :z (if (eq kind :cheer) 7 6) :policy :none :ttl ttl
                 :x (creature-x boat) :y (creature-y boat)
                 :data (list :boat boat :threat threat :boat-rise nil :tick tick :place place)))

(defun fishing-line-x (boat)
  "The column under BOAT's rod tip, just past its art on the facing side."
  (if (eq (creature-facing boat) :right)
      (+ (creature-x boat) (creature-dimensions boat))
      (1- (creature-x boat))))

(defun make-fisher (world &key facing)
  "Create the fisher's boat CREATURE entering WORLD off one edge (FACING
defaults to a random side) and stopping at a random column. Its data holds
the line, hook, and cheer creatures it will add, :BOAT-RISE (its height above
the waterline, for the storm sway), and the fishing state :PHASE and
:WAIT-UNTIL."
  (let* ((theme (world-theme world))
         (facing (or facing (random-facing)))
         (width (world-width world))
         (art-width (sprite-width +fisher-art+))
         (margin (floor width 5))
         (stop-x (random-between margin (max margin (- width margin art-width 1))))
         (y (boat-sway-row world +fisher-boat-rise+))
         ;; The hook rests on the row above the sand, like the decor does.
         (max-depth (max 1 (- (world-sand-top world) y 2))))
    (multiple-value-bind (x dx) (off-screen-entry facing art-width width +fisher-boat-speed+)
      (multiple-value-bind (role-styles style) (%fisher-boat-colors theme)
        (let ((boat (make-creature :world world :kind :fisher
                                   :frames (list +fisher-art+) :masks (list +fisher-mask+)
                                   :role-styles role-styles :style style
                                   :%trusted-frames-p t :%trusted-style-p t
                                   :facing facing :z 7 :policy :despawn
                                   :x x :y y :dx dx
                                   :data (list :phase :arrive :wait-until 0 :boat-rise +fisher-boat-rise+
                                               :stop-x stop-x :depth 1.0f0
                                               :max-depth max-depth
                                               :line nil :hook nil :cheer nil :prey nil
                                               :tick 'fisher-tick))))
          (let ((data (creature-data boat)))
            (setf (getf data :line)
                  ;; The :PLACE lets WORLD-RESIZE re-hang a part under the boat
                  ;; it has just moved, while paused too.
                  (%make-fisher-part world :line boat
                                     :tick 'fishing-line-tick :place 'fishing-line-tick)
                  (getf data :hook)
                  (%make-fisher-part world :hook boat
                                     :tick 'fishing-hook-tick :place 'fishing-hook-tick
                                     :threat +hook-threat+)
                  (getf data :cheer)
                  (%make-fisher-part world :cheer boat :ttl +fisher-cheer-ticks+)))
          boat)))))

(defun spawn-fisher-now (world)
  "Create the fisher event and add its boat to WORLD now; return the boat."
  (%add-world-creature world (make-fisher world)))

(defun restyle-fisher (world boat)
  (multiple-value-bind (role-styles style) (%fisher-boat-colors (world-theme world))
    (%set-creature-colors boat :style style :role-styles role-styles)))

(defun %add-fisher-part (world part)
  "Add PART to WORLD in WORLD's current theme: it was built with its boat, and
the theme may have changed since while it was not in WORLD to be restyled."
  (restyle-fisher-part world part)
  (%add-world-creature world part))

(defun restyle-fisher-part (world part)
  (let ((kind (creature-kind part)))
    (%adopt-sprite-prototype
     part (%fisher-part-prototype kind
                                  (%fisher-part-max-depth kind (getf (creature-data part) :boat))
                                  (world-theme world)))))

(register-creature-restyler :fisher #'restyle-fisher)
(register-creature-restyler :line #'restyle-fisher-part)
(register-creature-restyler :hook #'restyle-fisher-part)
(register-creature-restyler :cheer #'restyle-fisher-part)
