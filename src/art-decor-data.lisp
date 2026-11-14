;;;; src/art-decor-data.lisp -- the ocean background's art and masks. Pure
;;;; data; art-decor.lisp holds the builders that lay it out for a screen size
;;;; and theme. Every sprite is original, authored for this repository. Each
;;;; mask has its art's exact line shape (see MAKE-CREATURE): a non-space mask
;;;; character names the color role of the cell above it, and a mask character
;;;; under a space paints that space as a solid fill.
(in-package #:cl-asciiquarium)

(defparameter +castle-art+
  (format nil (concatenate 'string
                            "   /\\      /\\~% _||_ /--\\ _||_~%|    |    |    |~%"
                            "|  o | [] |  o |~%|____|____|____|"))
  "Original castle decoration: two crenellated towers flanking a gatehouse.")

(defparameter +castle-mask+
  (format nil (concatenate 'string
                            "   CC      CC~% cccc cccc cccc~%c    c    c    c~%"
                            "c  w c cc c  w c~%cccccccccccccccc"))
  "C castle highlight, c castle, w a lit window.")

(defparameter +rock-art+ (format nil "   .--.~% .(    ).~%(________)")
  "The rock the octopus lives under.")

(defparameter +rock-mask+ (format nil "   rrrr~% rrRRRRrr~%rrrrrrrrrr")
  "r rock, R the rock's lit face.")

(defparameter +vent-art+ (format nil "  .^.~% /   \\~%/_____\\")
  "The hydrothermal vent the bubble column rises from.")

(defparameter +vent-mask+ (format nil "  RmR~% r   r~%rrrrrrr")
  "r rock, R the rock's lit face, m the vent mouth in the bubble color.")

(defparameter +chest-art+ (format nil " .------.~% |__$$__|~% |______|")
  "The closed treasure chest.")

(defparameter +chest-mask+ (format nil " wwwwwwww~% wwwggwww~% wwwwwwww")
  "w chest wood, g gold.")

(defparameter +coral-art+ (format nil "  , ,~% \\|/|~%  \\|/~%   |")
  "A small branching coral.")

(defparameter +coral-mask+ (format nil "  a b~% abab~%  bab~%   a")
  "a and b the coral's two tones.")

(defparameter +starfish-art+ (format nil ".\\|/.~% /|\\")
  "A starfish resting on the sand.")

(defparameter +starfish-mask+ (format nil "aAaAa~% AaA")
  "a and A the starfish's two tones.")

(defparameter +seaweed-frames+
  (list (format nil "\\~%|~%/~%|~%\\")
        (format nil "/~%|~%\\~%|~%/"))
  "The two-frame sway a seaweed strand loops between.")

(defparameter +seaweed-mask+ (format nil "g~%G~%g~%G~%g")
  "g and G the seaweed's two alternating tones, shared by both frames.")

(defparameter +sun-art+ (format nil "\\ | /~%- O -~%/ | \\")
  "The midday sun.")

(defparameter +sun-mask+ (format nil "b b b~%b b b~%b b b"))

(defparameter +sunset-art+ (format nil "  .-''-.~% (      )")
  "The sun setting on the horizon.")

(defparameter +sunset-mask+ (format nil "  bbbbbb~% ffffffff"))

(defparameter +moon-art+ (format nil " .-.~%(  (~% `-'")
  "The crescent moon.")

(defparameter +moon-mask+ (format nil " bbb~%b  b~% bbb"))

(defparameter +cloud-art+ (format nil "  .--.~%.(    ).")
  "A small cloud.")

(defparameter +cloud-mask+ (format nil "  bbbb~%bbbbbbbb"))

(defparameter +ambient-current-motif+ ".   .    .  ~")

(defparameter +ripple-motif+ "-     -   -       -    ")

(defparameter +sand-motifs+
  '(".  ,   .     '  .   ,    .  "
    "  :   .   ,    .   :   '    "
    ".   '   .   :    ,   .   .  ")
  "The three sand rows' grain patterns, repeated across the screen width.")
