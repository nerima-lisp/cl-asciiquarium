;;;; t/zukan-test.lisp -- the dex file (src/app-zukan.lisp) and the `z' panel
;;;; (src/art-zukan.lisp). Every file test works inside its own fresh
;;;; temporary directory, never the home or XDG directories.
(in-package #:cl-asciiquarium/test)

(defmacro with-zukan-directory ((var) &body body)
  `(with-temporary-directory (,var "aq-zukan-") ,@body))

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

(defun %keeps-random-sequence-p (thunk)
  "True when calling THUNK leaves *RANDOM-STATE* drawing the same numbers as a
copy taken before the call: file I/O must not perturb a --seed run.
t/snapshot-test.lisp, loaded after this file, uses it too."
  (let* ((*random-state* (sb-ext:seed-random-state 7))
         (reference (make-random-state *random-state*)))
    (funcall thunk)
    (equal (loop repeat 8 collect (random 1000000))
           (let ((*random-state* reference))
             (loop repeat 8 collect (random 1000000))))))

(defun %directory-file-names (directory)
  (sort (mapcar #'file-namestring (uiop:directory-files directory)) #'string<))

(defun %zukan-octets (parts)
  "Concatenate PARTS, each a string (encoded as UTF-8) or a byte vector."
  (apply #'concatenate '(vector (unsigned-byte 8))
         (mapcar (lambda (part)
                   (if (stringp part) (sb-ext:string-to-octets part :external-format :utf-8) part))
                 parts)))

(describe "zukan-path"
  (it "puts the file under an absolute XDG_STATE_HOME"
    (expect (namestring (cl-asciiquarium::zukan-path "/x/state" #p"/home/u/"))
            :to-equal "/x/state/cl-asciiquarium/zukan.sexp"))
  (it "accepts an XDG_STATE_HOME with a trailing slash"
    (expect (namestring (cl-asciiquarium::zukan-path "/x/state/" #p"/home/u/"))
            :to-equal "/x/state/cl-asciiquarium/zukan.sexp"))
  (it "reads wildcard characters in XDG_STATE_HOME literally"
    (expect (uiop:native-namestring (cl-asciiquarium::zukan-path "/x/a*b" #p"/home/u/"))
            :to-equal "/x/a*b/cl-asciiquarium/zukan.sexp"))
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
  (it-each (("empty" ())
            ("a truncated form" ("(:zukan 1 :species (:dart"))
            ("a #. form" ("(:zukan 1 :species #.(progn (setf cl-asciiquarium/test::*zukan-read-eval-probe* t) nil))"))
            ("invalid UTF-8" ("(:zukan 1 :species (:" #(255 254) "))"))
            ("version 2" ("(:zukan 2 :species (:dart))"))
            ("a non-keyword species" ("(:zukan 1 :species (\"dart\"))"))
            ("a second form" ("(:zukan 1 :species (:dart)) (:extra)"))
            ("a duplicate species" ("(:zukan 1 :species (:dart :dart))"))
            ("a dotted species list" ("(:zukan 1 :species (:dart . :eel))"))
            ("a circular species list" ("(:zukan 1 :species #1=(:dart . #1#))"))
            ("a missing :species key" ("(:zukan 1)"))
            ("a bare atom" ("42"))
            ;; Read as is, 50,000 open parentheses exhaust SBCL's control
            ;; stack, which kills the process rather than signal an error.
            ("lists nested 50,000 deep"
             ("(:zukan 1 :species " #.(make-string 50000 :initial-element #\()))
            ("species nested one list deeper" ("(:zukan 1 :species ((:dart)))"))
            ("50,000 quote marks"
             ("(:zukan 1 :species (" #.(make-string 50000 :initial-element #\') ":dart))"))
            ("more than 65,536 characters"
             ("(:zukan 1 :species (:dart" #.(make-string 70000 :initial-element #\Space) "))")))
      "rejects a file with ~A without changing it, even on a save attempt"
      (description parts)
    (declare (ignore description))
    (setf *zukan-read-eval-probe* nil)
    (with-zukan-directory (dir)
      (let* ((bytes (%zukan-octets parts))
             (path (%write-zukan-bytes (%zukan-file dir) bytes)))
        (expect (multiple-value-list (cl-asciiquarium::load-zukan path)) :to-equal '(nil nil))
        (expect (cl-asciiquarium::save-zukan path '(:dart)) :to-be nil)
        (expect (equalp (%zukan-bytes path) bytes) :to-be-truthy)
        (expect (%directory-file-names dir) :to-equal '("zukan.sexp"))
        (expect *zukan-read-eval-probe* :to-be nil))))
  (it "reads parentheses inside escaped species names as part of the name"
    (with-zukan-directory (dir)
      (let ((path (%write-zukan-text (%zukan-file dir)
                                     "(:zukan 1 :species (:|((kraken| :a\\(b :dart))")))
        (expect (multiple-value-list (cl-asciiquarium::load-zukan path))
                :to-equal (list (list (intern "((kraken" :keyword) (intern "A(B" :keyword) :dart)
                                t)))))
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
        (expect (%directory-file-names dir) :to-equal '("blocker")))))
  (it "reports a write that fails after the staging file exists, removing it"
    (with-zukan-directory (dir)
      ;; A function cannot be printed readably, so PRIN1 fails mid-write.
      (expect (cl-asciiquarium::save-zukan (%zukan-file dir) (list #'identity)) :to-be nil)
      (expect (%directory-file-names dir) :to-be nil)))
  (it-each (("a successful save" nil)
            ("a save whose directory cannot be created" :blocker)
            ("a save failing after the staging file exists" :unprintable))
      "leaves the simulation's random sequence unchanged after ~A"
      (description failure)
    (declare (ignore description))
    (with-zukan-directory (dir)
      (%write-zukan-text (merge-pathnames "blocker" dir) "")
      (let ((path (if (eq failure :blocker)
                      (merge-pathnames "blocker/zukan.sexp" dir)
                      (%zukan-file dir)))
            (species (if (eq failure :unprintable) (list #'identity) '(:dart))))
        (expect (%keeps-random-sequence-p
                 (lambda () (cl-asciiquarium::save-zukan path species)))
                :to-be-truthy)))))

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
        (let ((count (cl-asciiquarium::zukan-save-if-grown world path 0)))
          (expect count :to-be 1)
          (expect (cl-asciiquarium::world-notification world) :to-equal "dex save failed")
          (setf (cl-asciiquarium::world-notification world) nil)
          (expect (cl-asciiquarium::zukan-save-if-grown world path count) :to-be count)
          (expect (cl-asciiquarium::world-notification world) :to-be nil))))))

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

(describe "make-world :discovered-species"
  (it "treats the stored species as discovered, announcing only a new rare one"
    (let ((world (make-world :width 80 :height 24 :fish-count 0
                             :discovered-species '(:golden))))
      (cl-asciiquarium::%add-world-creature world (make-fish world :species :golden))
      (expect (cl-asciiquarium::world-notification world) :to-be nil)
      (cl-asciiquarium::%add-world-creature world (make-fish world :species :oarfish))
      (expect (cl-asciiquarium::world-notification world) :to-equal "Discovered: oarfish")))
  (it "leaves the caller's list alone as species are discovered"
    (let* ((stored (list :golden))
           (world (make-world :width 80 :height 24 :fish-count 0 :discovered-species stored)))
      (cl-asciiquarium::%add-world-creature world (make-fish world :species :dart))
      (expect stored :to-equal '(:golden))))
  (it "counts only known species in the status bar"
    (let ((world (make-world :width 80 :height 24 :fish-count 0
                             :discovered-species '(:kraken :dart))))
      (cl-asciiquarium::world-refresh-hud world)
      (expect (search "dex 1/16"
                      (creature-art (find :hud (cl-asciiquarium::world-%creatures world)
                                          :key #'cl-asciiquarium::creature-kind)))
              :to-be-truthy))))
