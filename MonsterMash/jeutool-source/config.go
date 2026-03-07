// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "fmt"
import "os"
import "strings"
import "path/filepath"
import "text/scanner"

const CONFIG_FILE = "config.cfg"

var Config struct {
	iwad bool

	strife_tex bool
}

func WriteConfig(dirname string) {
	var sb strings.Builder

	fmt.Fprintf(&sb, "// this controls whether we build an IWAD or PWAD\n")
	fmt.Fprintf(&sb, "iwad = %v\n", Config.iwad)
	fmt.Fprintf(&sb, "\n")

	fmt.Fprintf(&sb, "// this controls the format of the TEXTURE1/2 lumps\n")
	fmt.Fprintf(&sb, "strife_tex = %v\n", Config.strife_tex)

	data := []byte(sb.String())

	filename := filepath.Join(dirname, CONFIG_FILE)

	err := TXT_Save(filename, data)
	if err != nil {
		Failure("saving %s: %s", CONFIG_FILE, err.Error())
		return
	}

	Message("Saved %s", CONFIG_FILE)
}

func ReadConfig(dirname string) {
	filename := filepath.Join(dirname, CONFIG_FILE)

	// NOTE: we don't need TXT_Load() here, the Scanner package
	//       already handles CR/LF endings and the unicode BOM.

	// the file is optional, hence no message here
	f, err := os.Open(filename)
	if err != nil {
		return
	}

	defer f.Close()

	var s scanner.Scanner

	s.Init(f)
	s.Error = func(s *scanner.Scanner, msg string) {
		// we ignore errors during parsing
	}

	for ParseLine(&s) != scanner.EOF {
		// keep parsing until end of file
	}

	if s.ErrorCount > 0 {
		Failure("there was %d errors reading %s", s.ErrorCount, CONFIG_FILE)
	} else {
		Message("Loaded %s", CONFIG_FILE)
	}
}

func ParseLine(s *scanner.Scanner) rune {
	tok := s.Scan()

	// nothing left?
	if tok == scanner.EOF {
		return tok
	}

	// first, we require a variable name
	if tok != scanner.Ident {
		return 0
	}

	name := s.TokenText()

	// second, we require an equals sign
	tok = s.Scan()
	if tok == scanner.EOF {
		return tok
	}
	if tok != '=' {
		return 0
	}

	// third, we require a value
	tok = s.Scan()
	if tok == scanner.EOF {
		return tok
	}
	if !(tok == scanner.Ident || tok == scanner.Int || tok == scanner.String) {
		return 0
	}

	value := s.TokenText()

	// unquote a string
	if tok == scanner.String {
		n, _ := fmt.Sscanf(value, "%q", &value)
		if n != 1 {
			return 0
		}
	}

	// finally, process what we got

	switch strings.ToLower(name) {
	case "iwad":
		Config.iwad = ParseBoolean(value)
	case "strife_tex":
		Config.strife_tex = ParseBoolean(value)
	default:
		Warning("unknown %s field: '%s'", CONFIG_FILE, name)
	}

	return 0
}

func ParseBoolean(s string) bool {
	// fmt.Sscanf is too lenient for bools, so roll our own
	switch strings.ToLower(s) {
	case "true", "1":
		return true
	case "false", "0":
		return false
	default:
		Warning("bad boolean in %s: '%s'", CONFIG_FILE, s)
		return false
	}
}

func ParseInteger(s string) (res int) {
	n, _ := fmt.Sscanf(s, "%d", &res)
	if n != 1 {
		Warning("bad integer in %s: '%s'", CONFIG_FILE, s)
	}
	return
}
