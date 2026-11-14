;;;; src/app-zukan.lisp -- the dex file: which species have ever been
;;;; discovered, kept across runs as one (:ZUKAN 1 :SPECIES LIST) form.
;;;; World code never calls into this file; the app loop does.
(in-package #:cl-asciiquarium)

(defun zukan-path (state-home home)
  "Return the dex file's pathname. STATE-HOME is the value of XDG_STATE_HOME
(or NIL); the XDG Base Directory spec says to ignore an empty or relative
value, which then falls back to HOME's .local/state/."
  (let ((base (if (and state-home (plusp (length state-home))
                       (char= (char state-home 0) #\/))
                  (uiop:parse-native-namestring state-home :ensure-directory t)
                  (merge-pathnames ".local/state/" home))))
    (merge-pathnames "cl-asciiquarium/zukan.sexp" base)))

(defun %zukan-species-p (species)
  "True when SPECIES is a proper list of distinct keywords."
  (and (listp species)
       (list-length species)    ; NIL for a circular list; a dotted one signals
       (every #'keywordp species)
       (= (length species) (length (remove-duplicates species)))))

(defun load-zukan (path)
  "Read the dex file at PATH. Return (VALUES SPECIES WRITABLE-P): the stored
species and T, NIL and T when there is no file, or NIL and NIL when the file
is anything but exactly one (:ZUKAN 1 :SPECIES LIST) form of distinct
keywords. Species this build does not know are kept. Every failure to open,
decode, or read the file counts as broken: the caller handles them all alike
(notify, never overwrite)."
  (handler-case
      (with-open-file (stream path :if-does-not-exist nil :external-format :utf-8)
        (if (null stream)
            (values nil t)
            (with-standard-io-syntax
              ;; KEYWORD keeps the file's names out of this package; no #. runs.
              (let* ((*read-eval* nil)
                     (*package* (find-package :keyword))
                     (form (read stream)))
                (if (and (typep form '(cons (eql :zukan)
                                       (cons (eql 1) (cons (eql :species) (cons t null)))))
                         (%zukan-species-p (fourth form))
                         (eq (read stream nil stream) stream))
                    (values (fourth form) t)
                    (values nil nil))))))
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
               (uiop:with-staging-pathname (staging path)
                 (with-open-file (stream staging :direction :output :if-exists :supersede
                                                 :external-format :utf-8)
                   (with-standard-io-syntax
                     (let ((*print-case* :downcase))
                       (prin1 (list :zukan 1 :species merged) stream)
                       (terpri stream)))))
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
