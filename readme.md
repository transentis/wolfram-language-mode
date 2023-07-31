# Wolfram Language Mode

An Emacs package that provides code highlighting for Wolfram Language. It "knows" all the Wolfram Language symbols and hightlights them using the keyword font. That way you can easily differentiate between your own functions and the Wolfram Language built-ins.

The package provides an interactive Wolfram Language REPL and it is also compatible with the Wolfram LSP server that is provided by the Wolfram Language. Using the LSP isn't just useful for Syntax checking, it also provides documentation for all Wolfram Language symbols.

The _Wolfram Language Mode_ package isn't available on MELPA yet, but you can easily install it locally.

## Setup Instructions

* Download the wolfram-language-mode.el and place it in a local directory, e.g. in `~/.emacs.d/lisp`
* Add the following to your `.emacs` file:

	``` elisp
	(add-to-list 'load-path (concat user-emacs-directory "lisp/" )) ;; use whatever directory you want here
	(load "wolfram-language-mode") ;; this loads the wolfram-language-mode
	(setq wolfram-program "<wolfram exectuable>");; the kernel used for the REPL, you only need to set this if you don't want the default "wolframscript"
	```

* Add the following lines to setup the Wolfram LSP for `eglot` - again you need to add a path to a WolframKernel here.

	``` elisp
	(with-eval-after-load 'eglot
		(add-to-list 'eglot-server-programs
		`(wolfram-language-mode . ("/Applications/Wolfram Engine.app/Contents/MacOS/WolframKernel" "-noinit" "-noprompt" "-nopaclet" "-noicon" "-nostartuppaclets" "-run" "Needs[\"LSPServer`\"];LSPServer`StartServer[]"))))
		 
	```

* Something similar should also work with other Emacs LSP packages.


## Usage

* The _Wolfram Language Mode_ should now start automatically when you open a .wl or .wls file. You can also start the mode using `M-x wolfram-language-mode`
* Start a REPL using `M-x run-wolfram-kernel`
* To stop the REPL first kill the Wolfram Kernel using `Exit[]`, then you can kill the emacs buffer.
* To start the language server call `M-x eglot`.
* Shut down the language server using `M-x eglot-shutdown-all`.

## History

The package is inspired by the _Wolfram Mode_ package provided by [Taichi Kawabata](https://github.com/kawabata/wolfram-mode). The interaction with the Wolfram REPL has been updated and the new package also contains a list of all current Wolfram Language symbols. The package is more minimalistic then the original one, e.g. it doesn't include the EPrint option.
