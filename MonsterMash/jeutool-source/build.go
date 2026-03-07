// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "fmt"
import "os"
import "io/ioutil"
import "strings"
import "path/filepath"

import "gitlab.com/andwj/wad"

type LumpBits struct {
	sub    string // e.g. "somedir/maps"
	base   string // e.g. "MAP03.wad"
	lump   string // e.g. "MAP03"
	ext    string // e.g. "wad"
	noconv bool   // do not convert (add the file as-is)
	x, y   int    // offsets
}

var (
	Skipped = fmt.Errorf("skipped a file")
)

var build_pnames map[string]int

func CmdBuild(names []string) error {
	if len(names) == 0 {
		return fmt.Errorf("missing filename for build command")
	} else if len(names) > 2 {
		return fmt.Errorf("too many filenames")
	}

	if Options.raw {
		return fmt.Errorf("--raw option is not needed for build")
	}

	filename := names[0]

	err := ValidateWadFilename(filename)
	if err != nil {
		return err
	}

	dirname := DeduceExtractionDir(filename)
	if len(names) >= 2 {
		dirname = names[1]
	}

	err = ValidateDirName(dirname)
	if err != nil {
		return err
	}

	// check whether dirname exists
	info, err := os.Stat(dirname)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("%s is not a directory", dirname)
	}

	w, err := wad.Create(filename)
	if err != nil {
		return err
	}

	defer w.Close()

	err = BuildReadPalette(dirname)
	if err != nil {
		return err
	}

	ShowBanner()

	Message("Input directory: %s", dirname)
	Message("Created WAD file: %s", filename)
	Message("Loaded palette: %s", palette_from)

	// the config file is optional
	ReadConfig(dirname)

	w.Iwad = Config.iwad

	// clear the PNAMES mapping
	build_pnames = nil

	for ns := _NS_FIRST; ns <= _NS_LAST; ns++ {
		BuildNamespace(w, dirname, ns)
	}

	err = w.Finish()
	if err != nil {
		Failure("finalizing WAD: %s", err.Error())
	} else {
		Message("Wrote WAD directory")
	}

	ShowSummary()

	return Ok
}

func BuildReadPalette(dirname string) error {
	// Note: this does not create the PLAYPAL lump, that is done by
	//       the regular lump importing code below.

	palette_from = "????"

	// ugh, need to support uppercase and lowercase here

	err := PaletteLoad(filepath.Join(dirname, "special", "PLAYPAL.png"))

	if err != nil {
		err = PaletteLoad(filepath.Join(dirname, "special", "playpal.png"))
	}

	if err != nil {
		err = PaletteLoad(filepath.Join(dirname, "special", "PLAYPAL.raw"))
	}

	if err != nil {
		err = PaletteLoad(filepath.Join(dirname, "special", "playpal.raw"))
	}

	if err != nil {
		err = PaletteLoad(filepath.Join(dirname, BASE_PAL_FILE))
	}

	if err != nil && Options.palette != "" {
		err = PaletteLoad(Options.palette)

		// since this is the last resort, show the full error
		if err != nil {
			return fmt.Errorf("load palette: %s\n", err.Error())
		}
	}

	if err != nil {
		return fmt.Errorf("no palette found (use --pal option)")
	}

	return Ok
}

func BuildNamespace(w *wad.Wad, dirname string, ns Namespace) {
	got_one := false

	subdir := filepath.Join(dirname, ns.DirName())

	BuildScanDirectory(w, subdir, ns, &got_one)

	// create the end marker (like F_END) if needed
	if got_one {
		BuildEndMarker(w, ns)
	}

	// if we added TEXTURE1/2, then create the PNAMES lump
	if build_pnames != nil {
		BuildCreatePNAMES(w)
		build_pnames = nil
	}
}

func BuildScanDirectory(w *wad.Wad, subdir string, ns Namespace,
	got_one *bool) {

	files, err := ioutil.ReadDir(subdir)

	if os.IsNotExist(err) {
		// a missing directory is normal
		return
	}
	if err != nil {
		Failure("scanning %s : %s", ns.DirName(), err.Error())
		return
	}

	if len(files) == 0 {
		return
	}

	Message("Importing %s...", ns.DirName())

	for _, info := range files {
		// ignore directories (except for raw levels)
		if info.IsDir() {
			ImportTryRawLevel(w, subdir, info.Name())
			continue
		}

		lb := &LumpBits{sub: subdir, base: info.Name()}

		// decode filename into a lump name (etc)
		lb.lump, lb.ext, lb.noconv, lb.x, lb.y, err = DecodeLumpName(lb.base)

		if err != nil {
			Failure("   %s: %s", lb.base, err.Error())
			continue
		}

		// validate usage of the '=' (no conversion) prefix
		if lb.noconv {
			if !(lb.ext == "png" || lb.ext == "wav") {
				Failure("   %s: the '=' prefix only usable on PNG or WAV",
					lb.base)
				continue
			}
			if ns == NS_UNKNOWN || ns == NS_Special ||
				ns == NS_Colormap || ns == NS_Trans {
				Failure("   %s: the '=' prefix not usable in %s dir",
					lb.base, ns.DirName())
				continue
			}
		}

		// validate usage of the ",XX,YY" offset syntax
		if lb.x != 0 || lb.y != 0 {
			if lb.ext != "png" || lb.noconv {
				Failure("   %s: cannot use X/Y offsets here", lb.base)
				continue
			}
		}

		// create the start marker (like F_START)
		if !*got_one {
			*got_one = true
			BuildStartMarker(w, ns)
		}

		// must lumps are handled by ImportLump
		if ns == NS_Level {
			err = ImportLevel(w, lb)
		} else {
			err = ImportLump(w, lb, ns)
		}

		if err == Skipped {
			Warning("   Skipped unknown file: %s", lb.base)
		} else if err != nil {
			Failure("   adding %s: %s", lb.base, err.Error())
		}
	}
}

func BuildStartMarker(w *wad.Wad, ns Namespace) {
	// handle some oddities
	switch ns {
	case NS_Font_A:
		w.WriteLump("FONTA_S", nil)
		return
	case NS_Font_AY:
		w.WriteLump("FONTAY_S", nil)
		return
	case NS_Font_B:
		w.WriteLump("FONTB_S", nil)
		return
	}

	letter := ns.Letter()
	if letter == "" {
		return
	}

	if !w.Iwad {
		// in pwads we use SS_START/END, PP_START/END and FF_START/END

		// but... pwads typically use FF_START..F_END for flats.
		// this provides better compatibility with the vanilla DOOM
		// engine (basically tricking it to find all the flats).
		switch letter {
		case "S", "P", "F":
			letter = letter + letter
		}
	}

	// this cannot fail, it merely updates the wad's directory
	_ = w.WriteLump(letter+"_START", nil)
}

func BuildEndMarker(w *wad.Wad, ns Namespace) {
	// handle some oddities
	switch ns {
	case NS_Font_A:
		w.WriteLump("FONTA_E", nil)
		return
	case NS_Font_AY:
		w.WriteLump("FONTAY_E", nil)
		return
	case NS_Font_B:
		w.WriteLump("FONTB_E", nil)
		return
	}

	letter := ns.Letter()
	if letter == "" {
		return
	}

	if !w.Iwad {
		// in pwads we use SS_START/END, PP_START/END and FF_START/END

		// but... pwads typically use FF_START..F_END for flats.
		// this provides better compatibility with the vanilla DOOM
		// engine (basically tricking it to find all the flats).
		switch letter {
		case "S", "P":
			letter = letter + letter
		}
	}

	// this cannot fail, it merely updates the wad's directory
	_ = w.WriteLump(letter+"_END", nil)
}

func BuildAddPatchName(name string) int {
	name = strings.ToUpper(name)

	// create the mapping on first usage
	if build_pnames == nil {
		build_pnames = make(map[string]int)
	}

	idx, ok := build_pnames[name]
	if ok {
		return idx
	}

	idx = len(build_pnames)

	build_pnames[name] = idx

	return idx
}

func BuildCreatePNAMES(w *wad.Wad) {
	data := PNAMES_Encode(build_pnames)

	err := w.WriteLump("PNAMES", data)

	if err != nil {
		Failure("   adding %s: %s", "PNAMES", err.Error())
		return
	}

	Verbose("   Created PNAMES lump")
}

//----------------------------------------------------------------------

func ImportLevel(w *wad.Wad, lb *LumpBits) error {
	// WISH : handle noconv levels (useful for Doom64Ex)

	if lb.ext != "wad" || lb.noconv {
		return Skipped
	}

	filename := filepath.Join(lb.sub, lb.base)

	in, err := wad.Open(filename)
	if err != nil {
		return err
	}

	defer in.Close()

	// find the level in the wad, produce an error if there is
	// none or more than one.
	lev_idx := -1

	for idx, lump := range in.Directory {
		if lump.LevelMarker != wad.NOT_A_LEVEL {
			if lev_idx >= 0 {
				return fmt.Errorf("multiple levels found")
			}
			lev_idx = idx
		}
	}

	if lev_idx < 0 {
		return fmt.Errorf("no levels found")
	}

	// Ok, copy all the lumps into the wad being built.
	// the only slightly tricky part is replacing the name of the
	// header lump (and potentially its GL-Nodes counterpart).

	idx := lev_idx

	gl_marker := "GL_" + in.Directory[lev_idx].Name

	for idx < len(in.Directory) {
		lump := in.Directory[idx]

		if idx > lev_idx && !lump.LevelPart {
			break
		}
		if idx > lev_idx && lump.LevelMarker != wad.NOT_A_LEVEL {
			// we have reached a different level
			break
		}

		data, err := in.ReadLump(lump)
		if err != nil {
			return fmt.Errorf("error reading level: %s", err.Error())
		}

		name := lump.Name
		if idx == lev_idx {
			name = lb.lump
		} else if name == gl_marker {
			name = "GL_" + lb.lump
		}

		err = w.WriteLump(name, data)
		if err != nil {
			return fmt.Errorf("error writing level: %s", err.Error())
		}

		idx++
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportTryRawLevel(w *wad.Wad, subdir, header string) {
	subdir = filepath.Join(subdir, header)

	// we detect a raw level by the presence of the same header
	// name in the subdirectory, for example: "MAP02/MAP02.raw"
	headfile := filepath.Join(subdir, header) + ".raw"

	_, err := os.Stat(headfile)
	if err != nil {
		// there is no raw level here
		return
	}

	files, err := ioutil.ReadDir(subdir)

	if err != nil {
		Failure("scanning %s : %s", subdir, err.Error())
		return
	}

	// filter the file list
	filtered := make([]*LumpBits, 0)

	for _, info := range files {
		if info.IsDir() {
			continue
		}

		lb := LumpBits{sub: subdir, base: info.Name()}

		lb.lump, lb.ext, lb.noconv, lb.x, lb.y, err = DecodeLumpName(lb.base)

		if err != nil {
			Failure("   %s: %s", lb.base, err.Error())
			continue
		}
		if lb.ext != "raw" {
			Failure("   %s: wrong extension for raw level part", lb.base)
			continue
		}

		filtered = append(filtered, &lb)
	}

	// NOTES:
	//
	// (1) reconstructing maps from raw lumps is not a core feature of
	//     this program, and the following infelicities are unlikely to
	//     be addressed.
	//
	// (2) there is no checking that the imported lumps form a valid
	//     level, including whether a UDMF map has its terminating
	//     ENDMAP lump.
	//
	// (3) files in the directory *other* than the ones named below
	//     will simply be ignored, and without any warnings.
	//
	// (4) no validation of the contents of the lumps is done.
	//

	num_errors := 0

	add_lump := func(name string) {
		for _, lb := range filtered {
			if lb.lump == name {
				err = ImportRawLump(w, lb)
				if err != nil {
					Failure("   adding %s: %s", lb.base, err.Error())
					num_errors++
				}
			}
		}
	}

	// the order of lumps here is chosen so that both normal and UDMF
	// format levels will be constructed properly (assuming all the
	// required lumps are present).

	header = strings.ToUpper(header)

	add_lump(header)
	add_lump("TEXTMAP")
	add_lump("THINGS")
	add_lump("LINEDEFS")
	add_lump("SIDEDEFS")
	add_lump("VERTEXES")
	add_lump("SEGS")
	add_lump("SSECTORS")
	add_lump("NODES")
	add_lump("ZNODES")
	add_lump("SECTORS")
	add_lump("REJECT")
	add_lump("BLOCKMAP")
	add_lump("BEHAVIOR")
	add_lump("SCRIPTS")
	add_lump("DIALOGUE")
	add_lump("ENDMAP")

	add_lump("GL_" + header)
	add_lump("GL_LEVEL")
	add_lump("GL_VERT")
	add_lump("GL_SEGS")
	add_lump("GL_SSECT")
	add_lump("GL_NODES")
	add_lump("GL_PVS")
}

func ImportLump(w *wad.Wad, lb *LumpBits, ns Namespace) error {
	// every namespace allows raw lumps, with the exception
	// of NS_Level (and that is handled elsewhere).
	//
	// NOTE 1: this also takes care of demo files (NS_Demo).
	// NOTE 2: we allow nothing else in NS_UNKNOWN namespace.

	switch lb.ext {
	case "raw", "dat", "lmp":
		return ImportRawLump(w, lb)
	}

	// check for common but unusable formats
	switch lb.ext {
	case "doc", "docx", "rtf", "pdf", "htm", "html":
		Failure("   %s: this is not a plain text format", lb.base)
		return Ok
	case "bmp", "ppm", "pict", "xpm", "tif", "tiff":
		Failure("   %s: this image format is not supported", lb.base)
		return Ok
	case "wma", "aac", "mp2", "au":
		Failure("   %s: this audio format is not supported", lb.base)
		return Ok
	}

	switch ns {
	case NS_Colormap, NS_Trans:
		if lb.ext == "png" {
			return ImportRawPixImage(w, lb, true)
		}

	case NS_Definition:
		if lb.ext == "txt" {
			return ImportTextLump(w, lb)
		}

	case NS_ACS:
		// ACC compiler output is an ".o" file
		if lb.ext == "o" {
			return ImportRawLump(w, lb)
		}

	case NS_Dialog:
		// the SCRIPT## lumps are binary, and the output of the
		// dialog compiler (USDC) is an ".o" file
		if strings.HasPrefix(lb.lump, "SCRIPT") && lb.ext == "o" {
			return ImportRawLump(w, lb)
		}
		// the DIALOG## lumps are text scripts
		if strings.HasPrefix(lb.lump, "DIALOG") && lb.ext == "txt" {
			return ImportTextLump(w, lb)
		}

	case NS_Model:
		switch lb.ext {
		case "mdl", "md2", "md3", "dmd", "3d":
			return ImportRawLump(w, lb)
		case "obj":
			return ImportTextLump(w, lb)
		}

	case NS_Voxel:
		// it seems ZDoom and derivatives only support KVX format.
		// supporting more here will also require an ability to detect
		// the different ones in the IdentifyLump() code.
		switch lb.ext {
		case "kvx":
			return ImportRawLump(w, lb)
		case "kv6", "vox":
			Failure("   %s: this format is not supported by ZDoom", lb.base)
			return Ok
		}

	case NS_PC_Spkr:
		if lb.ext == "csv" {
			return ImportPCSpeaker(w, lb)
		}

	case NS_Sound, NS_Voice:
		if lb.ext == "wav" && !lb.noconv {
			return ImportDMXSound(w, lb)
		}

		switch lb.ext {
		case "wav", "flac", "aif", "aiff", "voc", "mp3", "ogg":
			return ImportRawLump(w, lb)
		}

	case NS_Music:
		switch lb.ext {
		case "mus", "mid", "midi", "flac", "mp3", "ogg":
			return ImportRawLump(w, lb)
		case "mod", "s3m", "it", "xm":
			return ImportRawLump(w, lb)
		}

	case NS_Flat:
		if lb.ext == "png" && !lb.noconv {
			return ImportFlatImage(w, lb)
		}
		fallthrough

	case NS_Graphic, NS_Sprite, NS_Patch, NS_TX_Tex, NS_Hires,
		NS_Font_A, NS_Font_AY, NS_Font_B:
		if lb.ext == "png" && !lb.noconv {
			return ImportPatchImage(w, lb, ns)
		}

		switch lb.ext {
		case "png", "jpg", "jpeg", "gif", "pcx", "tga", "dds", "imgz":
			return ImportRawLump(w, lb)
		}

	case NS_Special:
		if lb.ext == "ans" || lb.ext == "ansi" {
			return ImportANSIScreen(w, lb)
		}

		switch lb.lump {
		case "PLAYPAL", "E2PAL":
			if lb.ext == "png" {
				return ImportPlaypal(w, lb)
			}
		case "COLORMAP":
			if lb.ext == "png" {
				return ImportRawPixImage(w, lb, true)
			}
		case "TEXTURE1", "TEXTURE2":
			if lb.ext == "txt" {
				return ImportTextureDef(w, lb)
			}
		case "E2END":
			if lb.ext == "png" {
				return ImportHereticE2END(w, lb)
			}
		case "STARTUP":
			if lb.ext == "png" {
				return ImportHexenSTARTUP(w, lb)
			}
		case "SNDCURVE":
			if lb.ext == "csv" {
				return ImportSndCurve(w, lb)
			}
		case "ANIMATED":
			if lb.ext == "txt" {
				return ImportAnimatedDef(w, lb)
			}
		case "SWITCHES":
			if lb.ext == "txt" {
				return ImportSwitchesDef(w, lb)
			}
		}

		// all other PNG images will be raw pixel blocks
		if lb.ext == "png" {
			// this detects e.g. FOGMAP in Hexen
			// (though it makes little difference here)
			is_colormap := strings.HasSuffix(lb.lump, "MAP")

			return ImportRawPixImage(w, lb, is_colormap)
		}
	}

	// when file extension is unknown, skip that file
	return Skipped
}

func ImportRawLump(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := ioutil.ReadFile(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportTextLump(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := TXT_Load(filename)
	if err != nil {
		return err
	}

	// check if the lump would not be detected as text.
	// [ but allow empty files ]
	if len(data) > 0 && !IdentifyTextLump(data) {
		Warning("   file does not seem to be text: %s", lb.base)
	}

	// for Strife, it is critical that LOGxxx lumps end with a
	// trailing NUL byte.
	if strings.HasPrefix(lb.lump, "LOG") {
		data = append(data, 0)
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportDMXSound(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := DMX_Audio_Load(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportPCSpeaker(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := PCSFX_Load(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	if !strings.HasPrefix(lb.lump, "DP") {
		Warning("   PC Speaker lump lacks 'DP' prefix: %s", lb.base)
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportSndCurve(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := SNDCURVE_Load(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportPatchImage(w *wad.Wad, lb *LumpBits, ns Namespace) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, _, _, err := PATCH_Load(filename, lb.x, lb.y)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportFlatImage(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, W, H, err := RAWPIX_Load(filename)
	if err != nil {
		return err
	}

	// TODO: check if size is weird
	_, _ = W, H

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportRawPixImage(w *wad.Wad, lb *LumpBits, is_colormap bool) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, W, H, err := RAWPIX_Load(filename)
	if err != nil {
		return err
	}

	// TODO: check if the size is weird.
	//       e.g. if lb.lump == "STRTBOT", want W == 16, H == 16
	_, _ = W, H

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportANSIScreen(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := ioutil.ReadFile(filename)
	if err != nil {
		return err
	}

	data2 := ANSI_Encode(data)

	err = w.WriteLump(lb.lump, data2)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportPlaypal(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := PLAYPAL_LoadImage(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportTextureDef(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := TEXTURE_Load(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportHereticE2END(w *wad.Wad, lb *LumpBits) error {
	/* determine which palette to use */

	PalettePush()

	defer PalettePop()

	palette_from = "????"

	// look for an E2PAL in the filesystem
	err := PaletteLoad(filepath.Join(lb.sub, "E2PAL.png"))

	if err != nil {
		err = PaletteLoad(filepath.Join(lb.sub, "e2pal.png"))
	}
	if err != nil {
		err = PaletteLoad(filepath.Join(lb.sub, "E2PAL.raw"))
	}
	if err != nil {
		err = PaletteLoad(filepath.Join(lb.sub, "e2pal.raw"))
	}

	if err != nil {
		// when the --pal option is a wad, try that
		if Options.palette != "" && HasExtension(Options.palette, "wad") {
			err = PaletteLoadFromWad(Options.palette, "E2PAL")
		}
	}

	if err != nil {
		// fallback: use the built-in copy
		Warning("   E2END: cannot find E2PAL palette, using built-in")
		PaletteSetHereticE2PAL()
	} else {
		Verbose("   E2END: loaded palette from: %s", palette_from)
	}

	filename := filepath.Join(lb.sub, lb.base)

	data, W, H, err := RAWPIX_Load(filename)
	if err != nil {
		return err
	}

	// check if size is weird
	if W != 320 || H != 200 {
		Warning("   E2END: image is weird size: %dx%d", W, H)
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportHexenSTARTUP(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := HexenSTARTUP_Load(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportAnimatedDef(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := ANIMATED_Load(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}

func ImportSwitchesDef(w *wad.Wad, lb *LumpBits) error {
	filename := filepath.Join(lb.sub, lb.base)

	data, err := SWITCHES_Load(filename)
	if err != nil {
		return err
	}

	err = w.WriteLump(lb.lump, data)
	if err != nil {
		return err
	}

	Verbose("   Added %-8s from %s", lb.lump, filename)
	return Ok
}
