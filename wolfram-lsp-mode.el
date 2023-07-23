;;; wolfram-mode.el --- Mathematica editing and inferior mode.  -*- lexical-binding: t -*-

;; Filename: wolfram-lsp-mode.el
;; Description: Wolfram Language editing and inferior mode that support Wolfram LSP server
;; Author: Oliver Grasl <oliver.grasl@transentis.com>
;; Based on the wolfram-mode package created by
;; Modified by: Taichi Kawabata <kawabata.taichi_at_gmail.com>
;; Modified by: Tomas Skrivan <skrivantomas_at_seznam.cz.cz>
;; Modified by: Ken Kang <kenkangxgwe_at_gmail.com>
;; Created: 2023-07-23
;; Keywords: languages, processes, tools
;; Namespace: wolfram-
;; URL: https://github.com/transentis/wolfram-lsp-mode/

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

;;; Commentary:

;; This provides basic editing features for Wolfram Language
;; (http://reference.wolfram.com/language/), based on `math++.el'
;; (http://chasen.org/~daiti-m/dist/math++.el).

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Mathematica is (C) Copyright 1988-2023 Wolfram Research, Inc.
;;
;; Protected by copyright law and international treaties.
;;
;; Unauthorized reproduction or distribution subject to severe civil
;; and criminal penalties.
;;
;; Mathematica, Wolfram Engine and Wolfram language are registered
;; trademarks of Wolfram Research.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



(require 'comint)
(require 'smie)

;; ** Customs Variables

(defgroup wolfram-lsp-mode nil
  "Editing Wolfram Language code"
  :group 'languages)

(defcustom wolfram-lsp-mode-hook nil
  "Normal hook run when entering `wolfram-lsp-mode'.
See `run-hooks'."
  :type 'hook
  :group 'wolfram-lsp-mode)

(defcustom wolfram-program "math"
  "Command to invoke at `run-wolfram'."
  :type 'string
  :group 'wolfram-lsp-mode)

(defcustom wolfram-program-arguments '()
  "Additional arguments to `wolfram-program'."
  :type '(repeat string)
  :group 'wolfram-lsp-mode)

(defcustom wolfram-indent 8
  "Basic Indentation for newline."
  :type 'integer
  :group 'wolfram-lsp-mode)

(defcustom wolfram-path nil
  "Directory in Mathematica $Path. Emacs has to be able to write in this directory."
  :type 'string
  :group 'wolfram-lsp-mode)

;; ** wolfram-mode

(defvar wolfram-lsp-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-m" 'newline-and-indent)
    (define-key map "]" 'wolfram-electric-braket)
    (define-key map ")" 'wolfram-electric-paren)
    (define-key map "}" 'wolfram-electric-brace)
    (define-key map "\C-c\C-r" 'wolfram-send-region)
    (define-key map "\C-c\C-e" 'wolfram-send-last-mathexp)
    (define-key map "\C-c\C-s" 'wolfram-send-last-mathexp)
    map)
  "Keymap for `wolfram-lsp-mode'.")

(defvar wolfram-lsp-mode-syntax-table
  (let ((syntax-table (make-syntax-table)))
    ;; white space
    (modify-syntax-entry ?  " " syntax-table)
    (modify-syntax-entry ?\t " " syntax-table)
    (modify-syntax-entry ?\f " " syntax-table)
    (modify-syntax-entry ?\n " " syntax-table)
    (modify-syntax-entry ?\^m " " syntax-table)

    ;; comments and parens
    (modify-syntax-entry ?\( "()1n" syntax-table)
    (modify-syntax-entry ?\) ")(4n" syntax-table)
    (modify-syntax-entry ?* "_ 23n" syntax-table)

    ;; pure parens
    (modify-syntax-entry ?\[ "(]" syntax-table)
    (modify-syntax-entry ?\] ")[" syntax-table)
    (modify-syntax-entry ?{ "(}" syntax-table)
    (modify-syntax-entry ?} "){" syntax-table)

    ;; punctuation
    (modify-syntax-entry ?= "." syntax-table)
    (modify-syntax-entry ?: "." syntax-table)
    (modify-syntax-entry ?% "." syntax-table)
    (modify-syntax-entry ?< "." syntax-table)
    (modify-syntax-entry ?> "." syntax-table)
    (modify-syntax-entry ?& "." syntax-table)
    (modify-syntax-entry ?\| "." syntax-table)
    (modify-syntax-entry ?_ "." syntax-table)
    (modify-syntax-entry ?/ "." syntax-table)
    (modify-syntax-entry ?! "." syntax-table)
    (modify-syntax-entry ?@ "." syntax-table)
    (modify-syntax-entry ?# "." syntax-table)
    (modify-syntax-entry ?\' "." syntax-table)

    ;; quotes
    (modify-syntax-entry ?\\ "\\" syntax-table)
    (modify-syntax-entry ?\" "\"" syntax-table)

    ;; for Math numbers, the following would be better as
    ;; parts of symbols
    (modify-syntax-entry ?- "_" syntax-table)
    (modify-syntax-entry ?. "_" syntax-table)
    (modify-syntax-entry ?\` "_" syntax-table)
    (modify-syntax-entry ?^ "_" syntax-table)

    (modify-syntax-entry ?$ "_" syntax-table)
    (modify-syntax-entry ?+ "_" syntax-table)

    syntax-table)
  "Syntax table used in `wolfram-lsp-mode'.")

(define-abbrev-table 'wolfram-lsp-mode-abbrev-table ())

(defvar wolfram-syntax-propertize-function
  (syntax-propertize-rules
   ("\\\\[[A-Z][A-Za-z]*]" (0 "_"))))

(defvar wolfram-font-lock-keywords
  '(
    ("^In\[[0-9]+\]:=" . font-lock-keyword-face)
    ("^Out\[[0-9]+\]=" . font-lock-keyword-face)
    ("^Out\[[0-9]+\]//[A-Za-z][A-Za-z0-9]*=" . font-lock-keyword-face)
    ("\\([A-Za-z][A-Za-z0-9`]*\\)[ \t]*[\[][ \t]*[\[]" 1 "default")
    ("\\([A-Za-z][A-Za-z0-9`]*\\)[ \t]*[\[]" 1 font-lock-function-name-face)
    ("//[ \t\f\n]*\\([A-Za-z][A-Za-z0-9`]*\\)" 1 font-lock-function-name-face)
    ("\\([A-Za-z][A-Za-z0-9`]*\\)[ \t\f\n]*/@" 1 font-lock-function-name-face)
    ("\\([A-Za-z][A-Za-z0-9`]*\\)[ \t\f\n]*//@" 1 font-lock-function-name-face)
    ("\\([A-Za-z][A-Za-z0-9`]*\\)[ \t\f\n]*@@" 1 font-lock-function-name-face)
    ("~[ \t]*\\([A-Za-z][A-Za-z0-9`]*\\)[ \t]*~" 1 font-lock-function-name-face)
    ("_[) \t]*\\?\\([A-Za-z][A-Za-z0-9`]*\\)" 1 font-lock-function-name-face)
    ("\\(&&\\)" 1 "default")
    ("&" . font-lock-function-name-face)
    ("\\\\[[A-Za-z][A-Za-z0-9]*\]" . font-lock-constant-face )
    ("$[A-Za-z0-9]+" . font-lock-variable-name-face )
    ("\\([A-Za-z0-9]+\\)[ \t]*\\->" 1 font-lock-type-face )
    ("<<[ \t\f\n]*[A-Za-z][A-Za-z0-9]*`[ \t\f\n]*[A-Za-z][A-Za-z0-9]*[ \t\f\n]*`"
     . font-lock-type-face )
    ("[A-Za-z][A-Za-z0-9]*::[A-Za-z][A-Za-z0-9]*" . font-lock-warning-face)
    ("\\[Calculating\\.\\.\\.\\]" . font-lock-warning-face)
    ("\\[Mathematica.*\\]" . font-lock-warning-face)
    ("^Interrupt>" . font-lock-warning-face)
    ("-Graphics-" . font-lock-type-face)
    ("-DensityGraphics-" . font-lock-type-face)
    ("-ContourGraphics-" . font-lock-type-face)
    ("-SurfaceGraphics-" . font-lock-type-face)
    ("-Graphics3D-" . font-lock-type-face)
    ("-GraphicsArray-" . font-lock-type-face)
    ("-Sound-" . font-lock-type-face)
    ("-CompiledCode-" . font-lock-type-face)))

(defvar wolfram-outline-regexp "\\((\\*\\|.+?:=\\)")

(defvar wolfram-smie-grammar
  (smie-prec2->grammar
   (smie-bnf->prec2
    `((head) (epsilon) (string)
      (expr (head "[" exprs "]")
            (expr "[[" exprs "]]")
            ("{" exprs "}")
            ("(" expr ")")
	    ("<|" exprs "|>")
            ;; message
            (expr "::" string)
            ;; statement separation
            (expr ";" expr)
            (expr "&")
            ;; delayed set
            (expr ":=" expr)
            (head "/:" expr ":=" expr)
            ;; set
            (expr "=" expr)
            (head "/:" expr "=" expr)
            (expr "+=" expr)
            (expr "-=" expr)
            (expr "*=" expr)
            (expr "/=" expr)
            ;; operation
            (expr "~" head "~" expr)
            (expr "@@" expr)
            (expr "==" expr)
            (expr "||" expr)
            (expr "&&" expr)
            (expr "+" expr)
            (expr "-" expr)
            (expr "*" expr)
            (expr "/" expr)
            (expr "^" expr)
            ;; application
            (expr ":" expr)
            (expr "/;" expr)
            (expr "//" expr))
      (exprs (epsilon)
             (expr)
             (exprs "," expr)))
    '((assoc ";")
      (assoc "::")
      (assoc "&")
      (assoc "/:")
      (assoc ":=" "=" "+=" "-=" "*=" "/=")
      (assoc "/;" ":" "//")
      (assoc "~")
      (assoc "@@" "==")
      (assoc "||" "&&")
      (assoc "+" "-")
      (assoc "*" "/")
      (assoc "^")
      (assoc "[[")))))

(defun wolfram-smie-rules (kind token)
  "Wolfram Language SMIE indentation function for KIND and TOKEN."
  (pcase (cons kind token)
    (`(:before . "[")
     (save-excursion
       (smie-default-backward-token)
       `(column . ,(current-column))))
    (`(:after . ":=") `(column . ,wolfram-indent))
    (`(:after . ,(or "]" "}" ")" "|>")) '(column . 0))
    (`(:after . ,(or "[" "{" "(" "<|"))
     (save-excursion
       (beginning-of-line)
       (skip-chars-forward " \t")
       `(column . ,(+ wolfram-indent (current-column)))))
    (`(,_ . ";") (smie-rule-separator kind))
    (`(,_ . ",") (smie-rule-separator kind))
    (`(:elem . ,_) 0)
    (t nil)))

(defalias 'wolfram-smie-forward-token 'smie-default-forward-token)
(defalias 'wolfram-smie-backward-token 'smie-default-backward-token)

;;;###autoload
(define-derived-mode wolfram-lsp-mode prog-mode "Wolfram Language"
  "Major mode for editing Wolfram Language files in Emacs using the Wolfram LSP server.

\\{wolfram-lsp-mode-map}
Entry to this mode calls the value of `wolfram-lsp-mode-hook'
if that value is non-nil."
  :syntax-table wolfram-lsp-mode-syntax-table
  :abbrev-table wolfram-lsp-mode-abbrev-table
  (smie-setup wolfram-smie-grammar #'wolfram-smie-rules
              :forward-token 'wolfram-smie-forward-token
              :backward-token 'wolfram-smie-backward-token)
  (wolfram-lsp-mode-variables))

(defun wolfram-lsp-mode-variables ()
  "Local variables for both Major and Inferior mode."
  (set-syntax-table wolfram-lsp-mode-syntax-table)
  ;; set local variables
  (setq-local comment-start "(*")
  (setq-local comment-end "*)")
  (setq-local comment-start-skip "(\\*")
  (set (make-local-variable 'syntax-propertize-function)
       wolfram-syntax-propertize-function)
  (setq-local font-lock-defaults '(wolfram-font-lock-keywords nil nil))
  (setq-local outline-regexp wolfram-outline-regexp))

(defun wolfram-electric (char arg)
  "Indent on closing a CHAR ARG times."
  (if (not arg) (setq arg 1) nil)
  (dotimes (_i arg) (insert char))
  (funcall indent-line-function)
  (blink-matching-open))

(defun wolfram-electric-paren (arg)
  "Indent on closing a paren ARG times."
  (interactive "p")
  (wolfram-electric ")" arg))

(defun wolfram-electric-braket (arg)
  "Indent on closing a braket ARG times."
  (interactive "p")
  (wolfram-electric "]" arg))

(defun wolfram-electric-brace (arg)
  "Indent on closing a brace ARG times."
  (interactive "p")
  (wolfram-electric "}" arg))

(defun wolfram-electric-assoc (arg)
  "Indent on closing a association ARG times."
  (interactive "p")
  (wolfram-electric "|>" arg))

;; * inferior Mathematica mode. *

(defun wolfram-proc ()
  (let ((proc (get-buffer-process (if (eq major-mode 'inferior-wolfram-lsp-mode)
				      (current-buffer)
				    "*wolfram*"))))
    (or proc
	(error "No current process.  Do M-x `run-wolfram'"))))

(defun wolfram-send-region (start end)
  "Send the current region to the inferior Wolfram process."
  (interactive "r")
  (comint-send-region (wolfram-proc) start end)
  (comint-send-string (wolfram-proc) "\C-j"))

(define-derived-mode inferior-wolfram-lsp-mode comint-mode "Inferior Wolfram Language"
  "Major mode for interacting with an inferior Wolfram Engine process"
  :abbrev-table wolfram-lsp-mode-abbrev-table
  (setq comint-prompt-regexp "^(In|Out)\[[0-9]*\]:?= *")
  (wolfram-lsp-mode-variables)
  (setq mode-line-process '(":%s"))
  (setq comint-process-echoes t))

;;;###autoload
(defun run-wolfram (cmd)
  "Run an inferior Mathematica process CMD, input and output via buffer *wolfram*."
  (interactive (list (if current-prefix-arg
                         (read-string "Run Mathematica: " wolfram-program)
                       wolfram-program)))
  (setq wolfram-program cmd)
  (let ((cmdlist (append (split-string-and-unquote wolfram-program)
                         wolfram-program-arguments)))
    (pop-to-buffer-same-window
     (set-buffer (apply 'make-comint-in-buffer "wolfram" (get-buffer "*wolfram*")
                        (car cmdlist) nil (cdr cmdlist)))))
  (inferior-wolfram-lsp-mode))

(defun wolfram-here-is-space ()
  (let ((ca (char-after))
	(cb (char-before)))
    (and ca cb
	 (string-match "[ \t\n]" (char-to-string ca))
	 (string-match "[ \t\n]" (char-to-string cb)))))

(defun wolfram-moveto-last-content ()
  (while (wolfram-here-is-space)
    (backward-char 1)))

(defun wolfram-moveto-first-content ()
  (while (wolfram-here-is-space)
    (forward-char 1)))

(defun wolfram-beginning-of-cell ()
  (wolfram-moveto-last-content)
  (if (re-search-backward "^$" nil t) (forward-char 1)
    (goto-char (point-min))))

(defun wolfram-end-of-cell ()
  (wolfram-moveto-first-content)
  (if (re-search-forward "^$" nil t) (backward-char 1)
    (goto-char (point-max))))

(defun wolfram-send-last-mathexp ()
  "Send the last math expression to the inferior Mathematica process."
  (interactive)
  (save-excursion
    (let ((wolfram-start (progn (wolfram-beginning-of-cell) (point)))
	  (wolfram-end (progn (wolfram-end-of-cell) (point))))
      (comint-send-region (wolfram-proc) wolfram-start wolfram-end)
      (comint-send-string (wolfram-proc) "\C-j"))))



;; * Provide *

(provide 'wolfram-lsp-mode)

;; Local Variables:
;; coding: utf-8-unix
;; time-stamp-pattern: "10/Modified:\\\\?[ \t]+%:y-%02m-%02d\\\\?\n"
;; End:

;;; wolfram-lsp-mode.el ends here
