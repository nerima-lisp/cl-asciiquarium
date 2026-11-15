;;;; src/app-zukan.lisp -- the dex file: which species have ever been
;;;; discovered, kept across runs as one (:ZUKAN 1 :SPECIES LIST) form.
;;;; World code never calls into this file; the app loop does.
(in-package #:cl-asciiquarium)

(defun %absolute-directory (value)
  "Return VALUE, an environment variable's value or NIL, as a directory
pathname when it is an absolute path, otherwise NIL."
  (and value
       (uiop:string-prefix-p "/" value)
       ;; Native parsing, so a `*' or `[' in the name is not read as a wildcard.
       ;; The appended slash makes it a directory: :ENSURE-DIRECTORY would
       ;; re-escape such characters into the directory component.
       (uiop:parse-native-namestring (concatenate 'string value "/"))))

(defun zukan-path (state-home home)
  "Return the dex file's pathname. STATE-HOME is the value of XDG_STATE_HOME
(or NIL); the XDG Base Directory spec says to ignore an empty or relative
value, which then falls back to HOME's .local/state/."
  (merge-pathnames "cl-asciiquarium/zukan.sexp"
                   (or (%absolute-directory state-home)
                       (merge-pathnames ".local/state/" home))))

(defun %zukan-species-p (species)
  "True when SPECIES is a proper list of distinct keywords."
  (and (listp species)
       (list-length species)    ; NIL for a circular list; a dotted one signals
       (every #'keywordp species)
       (= (length species) (length (remove-duplicates species)))))

(defparameter +zukan-max-characters+ 65536
  "The longest dex file LOAD-ZUKAN reads. A file naming every species is about
250 characters, so this leaves room for hundreds of species a newer build may
add while keeping a runaway file from being read whole.")

(defparameter +zukan-max-depth+ 2
  "How deeply lists nest in a dex file: the form, and its species list inside.")

(defun %zukan-text-safe-to-read-p (text)
  "True when READ can take TEXT without deep recursion: no list opens more than
+ZUKAN-MAX-DEPTH+ deep, and none of the characters ' ` , # appears. Each of
those starts a reader macro that reads another form, so a run of them nests
like parentheses do, and the format uses none of them. Characters inside
strings, |...| names, after a backslash, or in a ; comment are not counted.
The check runs before READ, which recurses once per nested form: a few tens
of thousands exhaust SBCL's control stack, and that ends the process instead
of signalling an error."
  (let ((depth 0) (state :code))
    (loop for i below (length text)
          for character = (char text i)
          do (ecase state
               (:escape (setf state :code))
               (:bar-escape (setf state :bar))
               (:string-escape (setf state :string))
               (:comment (when (char= character #\Newline) (setf state :code)))
               (:string (case character
                          (#\\ (setf state :string-escape))
                          (#\" (setf state :code))))
               (:bar (case character
                       (#\\ (setf state :bar-escape))
                       (#\| (setf state :code))))
               (:code (case character
                        (#\\ (setf state :escape))
                        (#\" (setf state :string))
                        (#\| (setf state :bar))
                        (#\; (setf state :comment))
                        (#\( (when (> (incf depth) +zukan-max-depth+)
                               (return-from %zukan-text-safe-to-read-p nil)))
                        (#\) (decf depth))
                        ((#\' #\` #\, #\#)
                         (return-from %zukan-text-safe-to-read-p nil))))))
    t))

(defun %read-zukan-text (stream)
  "Return STREAM's whole text, or NIL when it is longer than
+ZUKAN-MAX-CHARACTERS+."
  (let* ((buffer (make-string (1+ +zukan-max-characters+)))
         (end (read-sequence buffer stream)))
    (and (<= end +zukan-max-characters+)
         (subseq buffer 0 end))))

(defun load-zukan (path)
  "Read the dex file at PATH. Return (VALUES SPECIES WRITABLE-P): the stored
species and T, NIL and T when there is no file, or NIL and NIL when the file
is anything but exactly one (:ZUKAN 1 :SPECIES LIST) form of distinct
keywords, is longer than +ZUKAN-MAX-CHARACTERS+, or fails
%ZUKAN-TEXT-SAFE-TO-READ-P. Species this build does not know are kept. Every failure to
open, decode, or read the file counts as broken: the caller handles them all
alike (notify, never overwrite)."
  (handler-case
      (with-open-file (stream path :if-does-not-exist nil :external-format :utf-8)
        (if (null stream)
            (values nil t)
            (let ((text (%read-zukan-text stream)))
              (if (and text (%zukan-text-safe-to-read-p text))
                  (with-standard-io-syntax
                    ;; KEYWORD keeps the file's names out of this package; no #. runs.
                    (let ((*read-eval* nil)
                          (*package* (find-package :keyword)))
                      (multiple-value-bind (form end) (read-from-string text)
                        (if (and (typep form '(cons (eql :zukan)
                                               (cons (eql 1)
                                                     (cons (eql :species) (cons t null)))))
                                 (%zukan-species-p (fourth form))
                                 (eq (read-from-string text nil text :start end) text))
                            (values (fourth form) t)
                            (values nil nil)))))
                  (values nil nil)))))
    (error () (values nil nil))))

(defun save-zukan (path species)
  "Write the union of SPECIES and the species already stored at PATH, re-read
just now so a concurrent run's discoveries survive, via a staging file renamed
over PATH. Return T on success, NIL when the stored file is broken (it is left
untouched) or the write fails."
  (multiple-value-bind (stored writable-p) (load-zukan path)
    (and writable-p
         (handler-case
             (let ((merged (append stored (remove-if (lambda (name) (member name stored)) species))))
               (ensure-directories-exist path)
               ;; UIOP draws the staging file's name from *RANDOM-STATE*; a
               ;; private state keeps a --seed run's simulation unperturbed.
               (let ((*random-state* (make-random-state t)))
                 (uiop:with-staging-pathname (staging path)
                   (with-open-file (stream staging :direction :output :if-exists :supersede
                                                   :external-format :utf-8)
                     (with-standard-io-syntax
                       (let ((*print-case* :downcase))
                         (prin1 (list :zukan 1 :species merged) stream)
                         (terpri stream))))))
               t)
           (error () nil)))))

(defun zukan-save-if-grown (world path saved-count)
  "Save WORLD's discovered species to PATH when there are more than
SAVED-COUNT, notifying on failure. Return the count to compare against next
time; a failed save is retried at the next discovery, not every tick."
  (let ((count (length (world-discovered-species world))))
    (when (and (> count saved-count)
               (not (save-zukan path (world-discovered-species world))))
      (world-notify world "dex save failed"))
    count))
