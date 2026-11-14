;;;; src/app-snapshot.lisp -- the `p' key's photo: the renderer's screen saved
;;;; as a plain-text file. The world only raises a request; the poller in
;;;; app.lisp calls SAVE-SNAPSHOT, so all file I/O stays out of WORLD-ADVANCE.
(in-package #:cl-asciiquarium)

(defun screen-text (screen)
  "Return SCREEN's characters as text: every row with trailing spaces removed,
rows joined by #\\Newline, no newline after the last row. A double-width glyph
is followed by its spacer cell, as CL-TTY-KIT:SCREEN-ROW-STRING returns it."
  (with-output-to-string (out)
    (dotimes (y (screen-height screen))
      (when (plusp y)
        (write-char #\Newline out))
      (write-string (string-right-trim " " (cl-tty-kit:screen-row-string screen y))
                    out))))

(defun snapshot-directory (pictures-dir cwd)
  "Return the directory a snapshot is saved in: PICTURES-DIR (the value of
XDG_PICTURES_DIR, or NIL) when it is an absolute path, otherwise CWD."
  (if (and pictures-dir (plusp (length pictures-dir)) (char= (char pictures-dir 0) #\/))
      ;; Native parsing, so a `*' or `[' in the name is not read as a wildcard.
      ;; The appended slash makes it a directory: :ENSURE-DIRECTORY would
      ;; re-escape such characters into the directory component.
      (uiop:parse-native-namestring (concatenate 'string pictures-dir "/"))
      cwd))

(defun snapshot-file-name (second minute hour date month year n)
  "Return \"aquarium-YYYYMMDD-HHMMSS.txt\", with \"-N\" before the type when N is 1 or more."
  (format nil "aquarium-~4,'0D~2,'0D~2,'0D-~2,'0D~2,'0D~2,'0D~:[~;-~D~].txt"
          year month date hour minute second (plusp n) n))

(defun %open-new-snapshot-file (directory universal-time)
  "Create the first snapshot file for UNIVERSAL-TIME (local time) that does not
exist yet in DIRECTORY, returning its output stream."
  (multiple-value-bind (second minute hour date month year) (decode-universal-time universal-time)
    ;; Opening with :IF-EXISTS NIL is the existence test itself, so no other
    ;; file can appear between a check and the open.
    (loop for n from 0
          for stream = (open (merge-pathnames (snapshot-file-name second minute hour date month year n)
                                              directory)
                             :direction :output :if-exists nil :if-does-not-exist :create
                             :external-format :utf-8)
          when stream
            return stream)))

(defun save-snapshot (screen directory universal-time)
  "Write SCREEN-TEXT of SCREEN, ending in a newline, to a new file in DIRECTORY
named by SNAPSHOT-FILE-NAME for UNIVERSAL-TIME. Return the file's pathname, or
NIL when the file could not be created or written (a missing DIRECTORY is not
created). A file that fails mid-write is left behind, partial."
  (handler-case
      (let ((stream (%open-new-snapshot-file directory universal-time)))
        (unwind-protect
             (progn
               (write-string (screen-text screen) stream)
               (terpri stream))
          (close stream))
        (pathname stream))
    ((or file-error stream-error) () nil)))

(defun snapshot-notification (pathname)
  "Return the status-bar message for SAVE-SNAPSHOT's result PATHNAME:
\"Saved <path>\", or \"Snapshot failed\" for NIL. Characters outside printable
ASCII in the path are shown as `?' because notifications are ASCII only."
  (if pathname
      (concatenate 'string "Saved "
                   (map 'string (lambda (character)
                                  (if (char<= #\Space character #\~) character #\?))
                        (uiop:native-namestring pathname)))
      "Snapshot failed"))
