;;;; t/zukan-test.lisp -- the dex file (src/app-zukan.lisp) and the `z' panel
;;;; (src/art-zukan.lisp). Every file test works inside its own fresh
;;;; temporary directory, never the home or XDG directories.
(in-package #:cl-asciiquarium/test)

(defmacro with-zukan-directory ((var) &body body)
  "Bind VAR to a new empty directory under the system temporary directory for
BODY, deleting it and its contents afterwards."
  `(let ((,var (uiop:ensure-directory-pathname
                (merge-pathnames (format nil "aq-zukan-~36R"
                                         (random most-positive-fixnum (make-random-state t)))
                                 (uiop:temporary-directory)))))
     (ensure-directories-exist ,var)
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree ,var :validate t :if-does-not-exist :ignore))))

(defvar *zukan-read-eval-probe* nil
  "Set by a #. form in a dex file only if the reader evaluated it.")

(defun %zukan-file (directory)
  (merge-pathnames "zukan.sexp" directory))

(defun %write-zukan-bytes (path bytes)
  (with-open-file (stream path :direction :output :element-type '(unsigned-byte 8)
                               :if-exists :supersede)
    (write-sequence bytes stream))
  path)

(defun %write-zukan-text (path text)
  (%write-zukan-bytes path (sb-ext:string-to-octets text :external-format :utf-8)))

(defun %zukan-bytes (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      bytes)))

(defun %directory-file-names (directory)
  (sort (mapcar #'file-namestring (uiop:directory-files directory)) #'string<))

(defparameter +broken-zukan-files+
  (list (cons "empty" #())
        (cons "a truncated form" (sb-ext:string-to-octets "(:zukan 1 :species (:dart"))
        (cons "a #. form"
              (sb-ext:string-to-octets
               "(:zukan 1 :species #.(progn (setf cl-asciiquarium/test::*zukan-read-eval-probe* t) nil))"))
        (cons "invalid UTF-8" (concatenate 'vector (sb-ext:string-to-octets "(:zukan 1 :species (:")
                                           #(255 254) (sb-ext:string-to-octets "))")))
        (cons "version 2" (sb-ext:string-to-octets "(:zukan 2 :species (:dart))"))
        (cons "a non-keyword species" (sb-ext:string-to-octets "(:zukan 1 :species (\"dart\"))"))
        (cons "a second form" (sb-ext:string-to-octets "(:zukan 1 :species (:dart)) (:extra)"))
        (cons "a duplicate species" (sb-ext:string-to-octets "(:zukan 1 :species (:dart :dart))"))
        (cons "a dotted species list" (sb-ext:string-to-octets "(:zukan 1 :species (:dart . :eel))"))
        (cons "a circular species list" (sb-ext:string-to-octets "(:zukan 1 :species #1=(:dart . #1#))"))
        (cons "a missing :species key" (sb-ext:string-to-octets "(:zukan 1)"))
        (cons "a bare atom" (sb-ext:string-to-octets "42")))
  "Each (DESCRIPTION . BYTES) is a dex file LOAD-ZUKAN must reject.")

(describe "zukan-path"
  (it "puts the file under an absolute XDG_STATE_HOME"
    (expect (namestring (cl-asciiquarium::zukan-path "/x/state" #p"/home/u/"))
            :to-equal "/x/state/cl-asciiquarium/zukan.sexp"))
  (it "accepts an XDG_STATE_HOME with a trailing slash"
    (expect (namestring (cl-asciiquarium::zukan-path "/x/state/" #p"/home/u/"))
            :to-equal "/x/state/cl-asciiquarium/zukan.sexp"))
  (it-each ((nil) ("") ("rel/dir"))
      "falls back to ~~/.local/state for XDG_STATE_HOME ~S"
      (state-home)
    (expect (namestring (cl-asciiquarium::zukan-path state-home #p"/home/u/"))
            :to-equal "/home/u/.local/state/cl-asciiquarium/zukan.sexp")))

(describe "load-zukan and save-zukan"
  (it "round-trips (:dart :golden), creating the missing directories"
    (with-zukan-directory (dir)
      (let ((path (merge-pathnames "state/cl-asciiquarium/zukan.sexp" dir)))
        (expect (cl-asciiquarium::save-zukan path '(:dart :golden)) :to-be t)
        (expect (multiple-value-list (cl-asciiquarium::load-zukan path))
                :to-equal '((:dart :golden) t)))))
  (it "writes the one form in lowercase"
    (with-zukan-directory (dir)
      (let ((path (%zukan-file dir)))
        (cl-asciiquarium::save-zukan path '(:dart))
        (expect (uiop:read-file-string path :external-format :utf-8)
                :to-equal (format nil "(:zukan 1 :species (:dart))~%")))))
  (it "starts from nothing and may save when there is no file"
    (with-zukan-directory (dir)
      (expect (multiple-value-list (cl-asciiquarium::load-zukan (%zukan-file dir)))
              :to-equal '(nil t))))
  (it-each ((0) (1) (2) (3) (4) (5) (6) (7) (8) (9) (10) (11))
      "rejects broken file ~D without changing it, even on a save attempt"
      (index)
    (destructuring-bind (description . bytes) (nth index +broken-zukan-files+)
      (declare (ignore description))
      (with-zukan-directory (dir)
        (let ((path (%write-zukan-bytes (%zukan-file dir) (coerce bytes '(vector (unsigned-byte 8))))))
          (expect (multiple-value-list (cl-asciiquarium::load-zukan path)) :to-equal '(nil nil))
          (expect (cl-asciiquarium::save-zukan path '(:dart)) :to-be nil)
          (expect (equalp (%zukan-bytes path) bytes) :to-be-truthy)
          (expect (%directory-file-names dir) :to-equal '("zukan.sexp"))))))
  (it "does not evaluate a #. form"
    (with-zukan-directory (dir)
      (setf *zukan-read-eval-probe* nil)
      (cl-asciiquarium::load-zukan (%write-zukan-bytes (%zukan-file dir) (cdr (nth 2 +broken-zukan-files+))))
      (expect *zukan-read-eval-probe* :to-be nil)))
  (it "keeps species this build does not know and writes them back"
    (with-zukan-directory (dir)
      (let ((path (%write-zukan-text (%zukan-file dir) "(:zukan 1 :species (:kraken :dart))")))
        (expect (multiple-value-list (cl-asciiquarium::load-zukan path))
                :to-equal '((:kraken :dart) t))
        (expect (cl-asciiquarium::save-zukan path '(:golden :dart)) :to-be t)
        (expect (cl-asciiquarium::load-zukan path) :to-equal '(:kraken :dart :golden)))))
  (it "keeps species another run saved between this run's load and save"
    (with-zukan-directory (dir)
      (let ((path (%zukan-file dir)))
        (cl-asciiquarium::save-zukan path '(:dart))
        (%write-zukan-text path "(:zukan 1 :species (:eel :dart))")
        (expect (cl-asciiquarium::save-zukan path '(:golden :dart)) :to-be t)
        (expect (cl-asciiquarium::load-zukan path) :to-equal '(:eel :dart :golden)))))
  (it "leaves no staging file in the directory"
    (with-zukan-directory (dir)
      (let ((path (%zukan-file dir)))
        (cl-asciiquarium::save-zukan path '(:dart))
        (cl-asciiquarium::save-zukan path '(:dart :eel))
        (expect (%directory-file-names dir) :to-equal '("zukan.sexp")))))
  (it "reports a failed write when the directory cannot be created"
    (with-zukan-directory (dir)
      (%write-zukan-text (merge-pathnames "blocker" dir) "")
      (let ((path (merge-pathnames "blocker/zukan.sexp" dir)))
        (expect (multiple-value-list (cl-asciiquarium::load-zukan path)) :to-equal '(nil t))
        (expect (cl-asciiquarium::save-zukan path '(:dart)) :to-be nil)
        (expect (%directory-file-names dir) :to-equal '("blocker"))))))

(describe "zukan-save-if-grown"
  (it "saves only when the discoveries grew and returns the new count"
    (with-zukan-directory (dir)
      (let ((world (tiny-world))
            (path (%zukan-file dir)))
        (expect (cl-asciiquarium::zukan-save-if-grown world path 0) :to-be 0)
        (expect (probe-file path) :to-be nil)
        (setf (cl-asciiquarium::world-discovered-species world) '(:eel :dart))
        (expect (cl-asciiquarium::zukan-save-if-grown world path 0) :to-be 2)
        (expect (cl-asciiquarium::load-zukan path) :to-equal '(:eel :dart))
        (expect (cl-asciiquarium::world-notification world) :to-be nil))))
  (it "notifies a failed save and does not retry until the next discovery"
    (with-zukan-directory (dir)
      (%write-zukan-text (merge-pathnames "blocker" dir) "")
      (let ((world (tiny-world))
            (path (merge-pathnames "blocker/zukan.sexp" dir)))
        (setf (cl-asciiquarium::world-discovered-species world) '(:dart))
        (expect (cl-asciiquarium::zukan-save-if-grown world path 0) :to-be 1)
        (expect (cl-asciiquarium::world-notification world) :to-equal "dex save failed")))))

(defun %count-substring (needle haystack)
  (loop for start = (search needle haystack) then (search needle haystack :start2 (1+ start))
        while start
        count t))

(defun %zukan-world (discovered)
  (let ((world (make-world :width 80 :height 24 :fish-count 0)))
    (setf (cl-asciiquarium::world-discovered-species world) discovered)
    world))

(describe "zukan panel"
  (it "lists discovered names, ??? for the rest, and the count in its title"
    (let ((art (cl-asciiquarium::zukan-sprite (%zukan-world '(:golden :dart)))))
      (expect (search "dart" art) :to-be-truthy)
      (expect (search "golden✦" art) :to-be-truthy)
      (expect (search " dex 2/16 " art) :to-be-truthy)
      (expect (%count-substring "???" art) :to-be 14)))
  (it "counts only species this build knows"
    (expect (search " dex 1/16 " (cl-asciiquarium::zukan-sprite (%zukan-world '(:kraken :dart))))
            :to-be-truthy))
  (it "is a box of equal-width rows whose mask lines up with its art"
    (multiple-value-bind (art mask) (cl-asciiquarium::zukan-sprite (%zukan-world '(:oarfish :eel)))
      (let ((art-lines (cl-asciiquarium::split-sprite-lines art))
            (mask-lines (cl-asciiquarium::split-sprite-lines mask)))
        (expect (length art-lines) :to-be 10)
        (expect (length (remove-duplicates (mapcar #'length art-lines))) :to-be 1)
        (expect (mapcar #'length mask-lines) :to-equal (mapcar #'length art-lines)))))
  (it "fits the water of an 80x24 screen as a :zukan-overlay"
    (let* ((world (%zukan-world '(:golden :dart)))
           (overlay (cl-asciiquarium::make-zukan-overlay world)))
      (cl-asciiquarium::%add-world-creature world overlay)
      (multiple-value-bind (width height) (creature-dimensions overlay)
        (expect (<= (+ (creature-x overlay) width) 80) :to-be-truthy)
        (expect (< (+ (creature-y overlay) height -1) (cl-asciiquarium::world-sand-top world))
                :to-be-truthy))
      (let ((rows (%drawn-rows world)))
        (expect (some (lambda (row) (search "dex 2/16" row)) rows) :to-be-truthy)
        (expect (reduce #'+ rows :key (lambda (row) (%count-substring "???" row))) :to-be 14))))
  (it "draws only ASCII under --ascii"
    (let* ((world (%zukan-world '(:golden)))
           (art (let ((*ascii* t)) (creature-art (cl-asciiquarium::make-zukan-overlay world)))))
      (expect (every (lambda (character) (< (char-code character) 128)) art) :to-be-truthy)
      (expect (search "golden*" art) :to-be-truthy)))
  (it "is recolored for a new theme"
    (let* ((*color-mode* :truecolor)
           (world (%zukan-world '(:dart)))
           (overlay (cl-asciiquarium::make-zukan-overlay world))
           (before (cl-asciiquarium::creature-%role-styles overlay)))
      (cl-asciiquarium::%add-world-creature world overlay)
      (world-cycle-theme world)
      (expect (search "dart" (creature-art overlay)) :to-be-truthy)
      (expect (equalp (cl-asciiquarium::creature-%role-styles overlay) before) :to-be-falsy)
      (expect (equalp (cl-asciiquarium::creature-%role-styles overlay)
                      (nth-value 2 (cl-asciiquarium::zukan-sprite world)))
              :to-be-truthy))))
