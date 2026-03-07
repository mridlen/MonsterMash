// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

/*

JeuTool : a tool to compose and decompose WAD files.

by Andrew Apted, 2018.

*/
package main

import "fmt"
import "os"

import "gitlab.com/andwj/argv"
import "github.com/daviddengcn/go-colortext"
import "github.com/mattn/go-isatty"

const VERSION = "0.8.2"
const DATE_STR = "21 Oct 2018"

// command-line options
var Options struct {
	palette   string
	lowercase bool
	raw       bool

	verbose bool
	nocolor bool
	help    bool
	version bool
}

var Stats struct {
	errors   int
	warnings int
}

func FgColor(fg ct.Color, bright bool) {
	if !Options.nocolor {
		ct.Foreground(fg, bright)
	}
}

func FgReset() {
	if !Options.nocolor {
		ct.ResetColor()
	}
}

func Message(format string, a ...interface{}) {
	fmt.Printf(format, a...)
	fmt.Printf("\n")
}

func Verbose(format string, a ...interface{}) {
	if Options.verbose {
		FgColor(ct.Cyan, false)
		Message(format, a...)
		FgReset()
	}
}

func Failure(format string, a ...interface{}) {
	// keep any indent
	for len(format) > 0 && format[0] == ' ' {
		format = format[1:]
		fmt.Printf(" ")
	}

	FgColor(ct.Red, false)
	fmt.Printf("ERROR: ")
	Message(format, a...)
	FgReset()

	Stats.errors += 1
}

func Warning(format string, a ...interface{}) {
	// keep any indent
	for len(format) > 0 && format[0] == ' ' {
		format = format[1:]
		fmt.Printf(" ")
	}

	FgColor(ct.Yellow, false)
	fmt.Printf("Warning: ")
	Message(format, a...)
	FgReset()

	Stats.warnings += 1
}

//----------------------------------------------------------------------

func ShowBanner() {
	FgColor(ct.Cyan, false)
	fmt.Printf("=======================================================\n")
	fmt.Printf(" )|( ")

	FgColor(ct.Yellow, true)
	fmt.Printf(" JeuTool %s  (C) 2018 Andrew Apted, et al ", VERSION)

	FgColor(ct.Cyan, false)
	fmt.Printf(" )|( \n")
	fmt.Printf("=======================================================\n")

	FgReset()
	fmt.Printf("\n")
}

func ShowUsage() {
	ShowBanner()

	Message("Usage: jeutool <command> [FILE] [OPTIONS...]")
	Message("")
	Message("Available commands:")
	Message("   info     FILE.wad ...")
	Message("   list     FILE.wad")
	Message("   pipe     FILE.wad LUMP")
	Message("   extract  FILE.wad [DIR]")
	Message("   build    FILE.wad [DIR]")
	Message("")
	Message("Available options:")

	argv.Display(os.Stdout)
}

func ShowVersion() {
	Message("JeuTool %s  (%s)", VERSION, DATE_STR)
}

func ShowSummary() {
	// a summary of errors and warnings
	Message("")

	if Stats.errors > 0 {
		FgColor(ct.Red, true)
		Message("FAIL: there was %s, %s.",
			Pluralize(Stats.errors, "error"),
			Pluralize(Stats.warnings, "warning"))

	} else if Stats.warnings > 0 {
		FgColor(ct.Green, false)
		Message("No errors, but %s occurred.",
			Pluralize(Stats.warnings, "warning"))

	} else {
		FgColor(ct.Green, false)
		Message("Ok, all good.")
	}

	FgReset()
}

func main() {
	// parse the command-line
	argv.Generic("p", "pal", &Options.palette, "file", "path to palette or IWAD")
	argv.Enabler("l", "lower", &Options.lowercase, "use lowercase filenames")
	argv.Enabler("r", "raw", &Options.raw, "extract each lump as-is")
	argv.Gap()
	argv.Enabler("v", "verbose", &Options.verbose, "show each lump name")
	argv.Enabler("n", "nocolor", &Options.nocolor, "disable colorized output")
	argv.Enabler("h", "help", &Options.help, "display this help text")
	argv.Enabler("", "version", &Options.version, "display the version")

	err := argv.Parse()
	if err != nil {
		fmt.Fprintf(os.Stderr, "jeutool: %s\n", err.Error())
		os.Exit(1)
	}

	// turn off color when output is not a terminal
	if !isatty.IsTerminal(os.Stdout.Fd()) {
		Options.nocolor = true
	}

	unparsed := argv.Unparsed()

	cmd := ""
	if len(unparsed) > 0 {
		cmd = unparsed[0]
		unparsed = unparsed[1:]
	}

	if Options.version || cmd == "version" {
		ShowVersion()
		os.Exit(0)
	}

	if Options.help || cmd == "help" || cmd == "" {
		ShowUsage()
		os.Exit(0)
	}

	switch cmd {
	case "info":
		err = CmdInfo(unparsed)
	case "list":
		err = CmdList(unparsed)
	case "pipe":
		err = CmdPipe(unparsed)
	case "extract":
		err = CmdExtract(unparsed)
	case "build":
		err = CmdBuild(unparsed)
	default:
		err = fmt.Errorf("unknown command '%s'", cmd)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "jeutool: %s\n", err)
		os.Exit(1)
	}

	if Stats.errors > 0 {
		os.Exit(2)
	}
}
