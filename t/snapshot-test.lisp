;;;; t/snapshot-test.lisp -- the `p' key's photo (src/app-snapshot.lisp).
;;;; Every file test writes into its own fresh temporary directory passed as
;;;; SAVE-SNAPSHOT's DIRECTORY, never the home, XDG, or current directory.
(in-package #:cl-asciiquarium/test)

(defmacro with-snapshot-directory ((var) &body body)
  `(with-temporary-directory (,var "aq-snapshot-") ,@body))

(defun %file-text (pathname)
  (uiop:read-file-string pathname :external-format :utf-8))

(defun %expected-snapshot-text (world)
  "WORLD redrawn from scratch on a fresh screen, as a snapshot file holds it."
  (format nil "~{~A~^~%~}~%"
          (mapcar (lambda (row) (string-right-trim " " row)) (%drawn-rows world))))

(defun %rendered-world (&key help-p)
  "Return (VALUES WORLD RENDERER): a seeded 80x24 world advanced and rendered
incrementally 30 times, so fish have moved since the first full paint."
  (with-seeded-random-state (20260102)
    (let* ((world (make-world :width 80 :height 24))
           (renderer (make-renderer 80 24 :initial-cell (world-background-cell world))))
      (when help-p
        (cl-asciiquarium::world-toggle-help-overlay world))
      (dotimes (i 30)
        (world-advance world)
        (render-frame renderer world :stream (make-broadcast-stream)))
      (values world renderer))))

(defparameter *snapshot-time* (encode-universal-time 5 4 3 2 1 2026))

(describe "snapshot-file-name"
  (it "names the file by local date and time"
    (expect (cl-asciiquarium::snapshot-file-name 5 4 3 2 1 2026 0)
            :to-equal "aquarium-20260102-030405.txt"))
  (it "adds -N before the type when N is 1 or more"
    (expect (cl-asciiquarium::snapshot-file-name 5 4 3 2 1 2026 2)
            :to-equal "aquarium-20260102-030405-2.txt")))

(describe "snapshot-directory"
  (it "uses an absolute XDG_PICTURES_DIR as a directory"
    (expect (cl-asciiquarium::snapshot-directory "/home/u/Pictures" #p"/cwd/")
            :to-equal #p"/home/u/Pictures/"))
  (it "reads wildcard characters in the directory name literally"
    (expect (uiop:native-namestring (cl-asciiquarium::snapshot-directory "/a*b" #p"/cwd/"))
            :to-equal "/a*b/"))
  (it-each (("Pictures") ("") (nil))
      "falls back to the current directory for ~S"
      (value)
    (expect (cl-asciiquarium::snapshot-directory value #p"/cwd/") :to-equal #p"/cwd/")))

(describe "snapshot-notification"
  (it "reports the saved file's name, without its directory"
    (expect (cl-asciiquarium::snapshot-notification
             (uiop:parse-native-namestring "/tmp/写真/aquarium-20260102-030405.txt"))
            :to-equal "Saved aquarium-20260102-030405.txt"))
  (it "reports a failure"
    (expect (cl-asciiquarium::snapshot-notification nil) :to-equal "Snapshot failed")))

(describe "save-snapshot"
  (it "writes the incrementally rendered screen, equal to a full redraw of the same world"
    (multiple-value-bind (world renderer) (%rendered-world)
      (unwind-protect
           (with-snapshot-directory (directory)
             (let ((path (cl-asciiquarium::save-snapshot
                          (cl-asciiquarium::renderer-screen renderer) directory *snapshot-time*)))
               (expect (namestring path)
                       :to-equal (namestring (merge-pathnames "aquarium-20260102-030405.txt"
                                                              directory)))
               (expect (%file-text path) :to-equal (%expected-snapshot-text world))))
        (shutdown-renderer renderer))))

  (it "includes the help box when the help panel is open"
    (multiple-value-bind (world renderer) (%rendered-world :help-p t)
      (unwind-protect
           (with-snapshot-directory (directory)
             (let ((text (%file-text (cl-asciiquarium::save-snapshot
                                      (cl-asciiquarium::renderer-screen renderer)
                                      directory *snapshot-time*))))
               (expect (search "╭─ controls ─" text) :to-be-truthy)
               (expect (search "│ s       spawn shark" text) :to-be-truthy)
               (expect text :to-equal (%expected-snapshot-text world))))
        (shutdown-renderer renderer))))

  (it "takes the next free -N name in the same second and leaves existing files unchanged"
    (with-snapshot-directory (directory)
      (let ((first (merge-pathnames "aquarium-20260102-030405.txt" directory))
            (second (merge-pathnames "aquarium-20260102-030405-1.txt" directory)))
        (uiop:with-output-file (out first) (write-string "first" out))
        (uiop:with-output-file (out second) (write-string "second" out))
        (let ((path (cl-asciiquarium::save-snapshot (make-screen 3 2) directory *snapshot-time*)))
          (expect (file-namestring path) :to-equal "aquarium-20260102-030405-2.txt")
          (expect (%file-text path) :to-equal (format nil "~%~%"))
          (expect (%file-text first) :to-equal "first")
          (expect (%file-text second) :to-equal "second")))))

  (it "fails without creating anything when the directory does not exist"
    (with-snapshot-directory (directory)
      (let ((missing (merge-pathnames "missing/" directory)))
        (expect (cl-asciiquarium::save-snapshot (make-screen 3 2) missing *snapshot-time*)
                :to-be-null)
        (expect (uiop:directory-exists-p missing) :to-be-falsy)
        (expect (uiop:directory-files directory) :to-be-null))))

  (it "leaves the simulation's random sequence unchanged"
    (with-snapshot-directory (directory)
      (expect (%keeps-random-sequence-p
               (lambda () (cl-asciiquarium::save-snapshot (make-screen 3 2) directory *snapshot-time*)))
              :to-be-truthy))))
