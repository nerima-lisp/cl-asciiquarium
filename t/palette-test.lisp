;;;; t/palette-test.lisp
(in-package #:cl-asciiquarium/test)

(describe "rgb-color"
  (it "parses a hex string, passes an RGB list through, and resolves theme then fixed roles"
    (expect (rgb-color "#0E2629") :to-equal '(14 38 41))
    (expect (rgb-color '(1 2 3)) :to-equal '(1 2 3))
    (expect (rgb-color :bg :coral) :to-equal '(14 38 41))
    (expect (rgb-color :bg :abyss) :to-equal '(8 21 33))
    (expect (rgb-color :gold :moonlight) :to-equal '(242 209 75)))
  (it "signals for a role neither the theme nor the fixed table defines"
    (expect (lambda () (rgb-color :no-such-role :coral)) :to-throw 'asciiquarium-invalid-argument)
    (expect (lambda () (rgb-color 42)) :to-throw 'asciiquarium-invalid-argument)))

(describe "color-style"
  (it "emits 24-bit foreground and the theme background in :truecolor"
    (let ((*color-mode* :truecolor))
      (expect (color-style "#FF8F70" :theme :coral)
              :to-equal (make-style (style-fg 255 143 112) (cl-tty-kit:style-bg 14 38 41)))))
  (it "maps both colors to xterm 256-color indices in :ansi256"
    (let ((*color-mode* :ansi256))
      (expect (color-style "#FF8F70" :theme :coral)
              :to-equal (make-style (style-fg (cl-tty-kit:rgb-to-256 255 143 112))
                                    (cl-tty-kit:style-bg (cl-tty-kit:rgb-to-256 14 38 41))))))
  (it "paints only a 16-color foreground in :ansi16"
    (let ((*color-mode* :ansi16))
      (expect (color-style "#FF8F70" :theme :coral)
              :to-equal (make-style (style-fg (cl-tty-kit:rgb-to-ansi16 255 143 112))))))
  (it "leaves the background alone when :background is nil, and adds bold on request"
    (let ((*color-mode* :truecolor))
      (expect (color-style "#FFFFFF" :background nil :bold-p t)
              :to-equal (make-style :bold (style-fg 255 255 255)))))
  (it "returns nil in :mono and whenever *monochrome* is true"
    (let ((*color-mode* :mono))
      (expect (color-style "#FFFFFF" :theme :coral) :to-be nil))
    (let ((*color-mode* :truecolor)
          (cl-asciiquarium::*monochrome* t))
      (expect (color-style "#FFFFFF" :theme :coral) :to-be nil))))

(describe "mask-role-styles"
  (it "maps the six fish mask roles, with white stripes and the rare glow light"
    (let* ((*color-mode* :truecolor)
           (styles (mask-role-styles '("#5FD7E6" "#2F9FB3" "#1F6F80" "#F4FBFF") :theme :abyss)))
      (expect (sort (mapcar #'car styles) #'char<) :to-equal (sort (list #\b #\e #\f #\l #\s #\t) #'char<))
      (expect (cdr (assoc #\b styles)) :to-equal (color-style "#5FD7E6" :theme :abyss))
      (expect (cdr (assoc #\e styles)) :to-equal (color-style "#F4FBFF" :theme :abyss))
      (expect (cdr (assoc #\s styles)) :to-equal (color-style "#FFFFFF" :theme :abyss))
      (expect (cdr (assoc #\l styles)) :to-equal (color-style "#FFE08A" :theme :abyss))))
  (it "lets extra roles add new mask letters and override built-in ones"
    (let* ((*color-mode* :truecolor)
           (styles (mask-role-styles '("#000000" "#000000" "#000000" "#000000")
                                     :theme :coral
                                     :extra-roles '((#\g . :gold) (#\b . "#FFFFFF")))))
      (expect (cdr (assoc #\g styles)) :to-equal (color-style :gold :theme :coral))
      (expect (cdr (assoc #\b styles)) :to-equal (color-style "#FFFFFF" :theme :coral))
      (expect (count #\b styles :key #'car) :to-be 1))))
