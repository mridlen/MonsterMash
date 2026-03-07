// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "fmt"
import "os"
import "strings"
import "path/filepath"

import "gitlab.com/andwj/wad"

const BASE_PAL_FILE = "base-pal.txt"

func CmdPipe(names []string) error {
	if len(names) == 0 {
		return fmt.Errorf("missing filename for pipe command")
	} else if len(names) == 1 {
		return fmt.Errorf("missing lump name for pipe command")
	} else if len(names) > 2 {
		return fmt.Errorf("too many filenames")
	}

	filename := names[0]

	err := ValidateWadFilename(filename)
	if err != nil {
		return err
	}

	lumpname := names[1]
	lumpname = strings.ToUpper(lumpname)

	w, err := wad.Open(filename)
	if err != nil {
		// the error already has the filename, so we don't wrap it
		return err
	}

	defer w.Close()

	lump := w.FindLump(lumpname)
	if lump == nil {
		return fmt.Errorf("lump not found: %s", lumpname)
	}

	data, err := w.ReadLump(lump)
	if err != nil {
		return fmt.Errorf("read error in %s lump: %s", lumpname, err.Error())
	}

	_, err = os.Stdout.Write(data)
	return err
}

//----------------------------------------------------------------------

func CmdExtract(names []string) error {
	if len(names) == 0 {
		return fmt.Errorf("missing filename for extract command")
	} else if len(names) > 2 {
		return fmt.Errorf("too many filenames")
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

	w, err := wad.Open(filename)
	if err != nil {
		// the error already has the filename, so we don't wrap it
		return err
	}

	defer w.Close()

	err = ExtractReadPalette(w)
	if err != nil {
		return err
	}

	err = os.Mkdir(dirname, os.ModeDir|0755)
	if err != nil {
		return err
	}

	ShowBanner()

	Message("Opened WAD file: %s", filename)
	Message("Created output dir: %s", dirname)

	Config.iwad = w.Iwad

	ExtractWritePalette(dirname)

	// analyse each lump to determine its file format.
	// this can also change which namespace the lump is in,
	// which is why we do this now instead of on-the-fly.

	wd2 := AnalyseWadDir(w)

	for _, lump := range wd2.lumps {
		err := IdentifyLump(wd2, lump)
		if err != nil {
			Failure("identifying %s: %s", lump.Name, err.Error())
		}
	}

	for ns := _NS_FIRST; ns <= _NS_LAST; ns++ {
		ExtractNamespace(wd2, ns, dirname)
	}

	// this may fail, but it is not a show-stopper
	WriteConfig(dirname)

	Message("Closing WAD file")

	ShowSummary()

	return Ok
}

func ExtractReadPalette(w *wad.Wad) error {
	lump := w.FindLump("PLAYPAL")

	if lump != nil {
		data, err := w.ReadLump(lump)
		if err == nil {
			err = PaletteLoadBuffer(data)
		}
		if err == nil {
			return Ok
		}

		return fmt.Errorf("read playpal: %s\n", err.Error())
	}

	if Options.palette != "" {
		err := PaletteLoad(Options.palette)
		if err != nil {
			return fmt.Errorf("load palette: %s\n", err.Error())
		}
		return Ok
	}

	if Options.raw {
		// a palette is not needed to rebuild the wad when
		// everything has been extracted as raw data.  But
		// this means base-pal.txt will be completely black.
		return Ok
	}

	return fmt.Errorf("no PLAYPAL found in wad (use --pal option)")
}

func ExtractWritePalette(dirname string) {
	// save the palette into a file, so that a future build command
	// has something to use when there is no PLAYPAL lump extracted.

	filename := filepath.Join(dirname, BASE_PAL_FILE)

	err := PaletteSaveText(filename)
	if err != nil {
		Failure("saving base palette: %s", err.Error())
		return
	}

	Message("Saved %s", BASE_PAL_FILE)
}

func ExtractNamespace(wd2 *WadExtra, ns Namespace, dirname string) {
	// filter out lumps we don't care about
	filtered := make([]*LumpExtra, 0)

	for _, lump := range wd2.lumps {
		if lump.handled {
			continue
		}
		if lump.namespace != ns {
			continue
		}

		// skip markers and other junk
		if lump.format == FMT_MARKER {
			continue
		}
		if lump.format == FMT_JUNK && !Options.raw {
			continue
		}

		// for levels we only want the header lump
		if ns == NS_Level && lump.LevelMarker == wad.NOT_A_LEVEL {
			continue
		}

		filtered = append(filtered, lump)
	}

	// don't create empty directories when nothing in the namespace
	if len(filtered) == 0 {
		return
	}

	subdir := filepath.Join(dirname, ns.DirName())

	err := os.Mkdir(subdir, os.ModeDir|0755)
	if err != nil {
		// we don't fail here, instead we allow each lump to fail
		Warning("cannot create directory: %s", err.Error())
	}

	Message("Extracting %s...", ns.DirName())

	for _, lump := range filtered {
		lump.handled = true

		var err error

		// must lumps are handled by ExtractLump
		if ns == NS_Level {
			err = ExtractLevel(wd2, lump.index, subdir)
		} else {
			err = ExtractLump(wd2, lump, subdir)
		}

		if err != nil {
			Failure("   saving %s: %s", lump.Name, err.Error())
		}
	}
}

//----------------------------------------------------------------------

func ExtractLevel(wd2 *WadExtra, idx int, subdir string) error {
	// levels are extracted to individual WAD files
	// (except in --raw mode)

	lump := wd2.lumps[idx]
	orig_name := lump.Name

	if Options.raw {
		return ExtractRawLevel(wd2, idx, subdir)
	}

	filename := EncodeLumpName(subdir, lump.Name, "wad", false, 0, 0)

	out, err := wad.Create(filename)
	if err != nil {
		return err
	}

	defer out.Close()

	// iterate over each lump of the level
	for {
		data, err := wd2.ReadLump(lump.Lump)
		if err != nil {
			return err
		}

		err = out.WriteLump(lump.Name, data)
		if err != nil {
			return err
		}

		idx++

		if idx >= len(wd2.lumps) {
			break
		}

		lump = wd2.lumps[idx]

		if !lump.LevelPart {
			break
		}
		if lump.LevelMarker != wad.NOT_A_LEVEL {
			// we have reached a different level
			break
		}
	}

	out.Finish()

	Verbose("   Saved %-8s to %s", orig_name, filename)
	return Ok
}

func ExtractRawLevel(wd2 *WadExtra, idx int, subdir string) error {
	lump := wd2.lumps[idx]

	subdir = EncodeLumpName(subdir, lump.Name, "", false, 0, 0)

	err := os.Mkdir(subdir, os.ModeDir|0755)
	if err != nil {
		return err
	}

	// iterate over each lump of the level
	for {
		err := ExtractRawLump(wd2, lump, "raw", subdir)
		if err != nil {
			return err
		}

		idx++

		if idx >= len(wd2.lumps) {
			break
		}

		lump = wd2.lumps[idx]

		if !lump.LevelPart {
			break
		}
		if lump.LevelMarker != wad.NOT_A_LEVEL {
			// we have reached a different level
			break
		}
	}

	return Ok
}

func ExtractLump(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	// in raw mode, *everything* is extracted as raw data
	if Options.raw {
		return ExtractRawLump(wd2, lump, "raw", dirname)
	}

	// text lumps require a bit of massaging
	if lump.format == FMT_TEXT {
		return ExtractTextLump(wd2, lump, "txt", dirname)
	}

	// formats with a known file extension are generally
	// exported as-is (no conversion).
	ext := lump.format.Extension()
	if ext != "" {
		return ExtractRawLump(wd2, lump, ext, dirname)
	}

	switch lump.Name {
	case "PLAYPAL", "E2PAL":
		return ExtractPlaypal(wd2, lump, dirname)

	case "TEXTURE1", "TEXTURE2":
		return ExtractTextureDef(wd2, lump, dirname)

	case "PNAMES":
		// ignore PNAMES here
		return Ok

	case "E2END":
		return ExtractHereticE2END(wd2, lump, dirname)

	case "STARTUP":
		return ExtractHexenSTARTUP(wd2, lump, dirname)

	case "SNDCURVE":
		return ExtractSndCurve(wd2, lump, dirname)

	case "ANIMATED":
		return ExtractAnimatedDef(wd2, lump, dirname)

	case "SWITCHES":
		return ExtractSwitchesDef(wd2, lump, dirname)
	}

	// by convention, demos use the LMP extension
	if lump.namespace == NS_Demo {
		return ExtractRawLump(wd2, lump, "lmp", dirname)
	}

	if lump.namespace == NS_PC_Spkr {
		return ExtractPCSpeaker(wd2, lump, dirname)
	}

	switch lump.format {
	case FMT_DMX_SND:
		return ExtractDMXSound(wd2, lump, dirname)

	case FMT_PATCH:
		return ExtractPatchImage(wd2, lump, dirname)

	case FMT_FLAT:
		return ExtractFlatImage(wd2, lump, dirname)

	case FMT_RAW_PIX:
		return ExtractRawPixImage(wd2, lump, dirname)

	case FMT_COLORMAP:
		return ExtractColormap(wd2, lump, dirname)

	case FMT_ANSI:
		return ExtractANSIScreen(wd2, lump, dirname)

	default:
		// when in doubt, just save it as a raw file
		return ExtractRawLump(wd2, lump, "raw", dirname)
	}
}

func ExtractRawLump(wd2 *WadExtra, lump *LumpExtra, ext, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	noconv := false
	if ext == "png" || ext == "wav" {
		noconv = true
	}

	filename := EncodeLumpName(dirname, lump.Name, ext, noconv, 0, 0)

	f, err := os.Create(filename)
	if err != nil {
		return err
	}

	defer SafeClose(f, filename)

	_, err = f.Write(data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractTextLump(wd2 *WadExtra, lump *LumpExtra, ext, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, ext, false, 0, 0)

	err = TXT_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractDMXSound(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "wav", false, 0, 0)

	err = DMX_Audio_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractPCSpeaker(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "csv", false, 0, 0)

	err = PCSFX_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractSndCurve(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "csv", false, 0, 0)

	err = SNDCURVE_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractPatchImage(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	OX, OY := PATCH_GetOffsets(data)

	// offsets are meaningless for texture patches, so inhibit them
	// for that particular case.
	if lump.namespace == NS_Patch {
		OX, OY = 0, 0
	}

	filename := EncodeLumpName(dirname, lump.Name, "png", false, OX, OY)

	err = PATCH_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractFlatImage(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	// determine an appropriate size
	var W, H int

	// TODO : tabulate these...
	switch len(data) {
	case 64 * 64:
		W, H = 64, 64
	case 64 * 65:
		W, H = 64, 65
	case 64 * 128:
		W, H = 64, 128
	case 128 * 128:
		W, H = 128, 128
	case 128 * 256:
		W, H = 128, 256
	case 256 * 256:
		W, H = 256, 256
	default:
		return fmt.Errorf("flat is weird size: %d", len(data))
	}

	filename := EncodeLumpName(dirname, lump.Name, "png", false, 0, 0)

	err = RAWPIX_Save(filename, data, W, H)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractRawPixImage(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	// determine an appropriate size
	// [ TODO: review this, maybe it should check lump name... ]
	var W, H int

	switch len(data) {
	case 320 * 200: // numerous full-screen images
		W, H = 320, 200
	case 320 * 158: // AUTOPAGE
		W, H = 320, 158
	case 48 * 48: // STRTBOT
		W, H = 48, 48
	case 32 * 64: // STRTPx1
		W, H = 32, 64
	case 16 * 16: // STRTLZx
		W, H = 16, 16
	default:
		return fmt.Errorf("rawpix is weird size: %d", len(data))
	}

	filename := EncodeLumpName(dirname, lump.Name, "png", false, 0, 0)

	err = RAWPIX_Save(filename, data, W, H)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractANSIScreen(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	if len(data) != 25*80*2 {
		Warning("   %s: weird size for ANSI text screen", lump.Name)
	}

	filename := EncodeLumpName(dirname, lump.Name, "ans", false, 0, 0)

	f, err := os.Create(filename)
	if err != nil {
		return err
	}

	defer SafeClose(f, filename)

	decode := ANSI_Decode(data)

	_, err = f.Write(decode)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractColormap(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	// determine an appropriate size
	W := 256
	H := int(lump.Length) / W

	if lump.Length == 256 {
		W = 16
		H = 16
	}

	filename := EncodeLumpName(dirname, lump.Name, "png", false, 0, 0)

	err = RAWPIX_Save(filename, data, W, H)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractPlaypal(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "png", false, 0, 0)

	err = PLAYPAL_SaveImage(filename, FullPalette(data))
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractTextureDef(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	// find the PNAMES lump, fail if not present.
	//
	// Rationale: a few pwads may exist with TEXTURE1/2 but lacking
	// a PNAMES lump, relying on the one in the IWAD.  But this is
	// quite error-prone, using a different IWAD would break it.
	// Hence I think supported that practice is a bad idea.

	pname_lump := wd2.FindLump("PNAMES")
	if pname_lump == nil {
		return fmt.Errorf("no PNAMES lump in wad")
	}

	pname_data, err := wd2.ReadLump(pname_lump)
	if err != nil {
		return fmt.Errorf("failed to read PNAMES: %s", err.Error())
	}

	pnames, err := PNAMES_Decode(pname_data)
	if err != nil {
		return fmt.Errorf("failed to read PNAMES: %s", err.Error())
	}

	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "txt", false, 0, 0)

	err = TEXTURE_Save(filename, data, pnames)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractHereticE2END(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	W, H := 320, 200

	if len(data) != W*H {
		return fmt.Errorf("rawpix is weird size: %d", len(data))
	}

	/* determine which palette to use */

	PalettePush()

	defer PalettePop()

	// look in wad file for E2PAL, then try Options.palette
	pal_lump := wd2.FindLump("E2PAL")

	if pal_lump != nil {
		data, err := wd2.ReadLump(pal_lump)
		if err == nil {
			err = PaletteLoadBuffer(data)
		}
		if err != nil {
			return fmt.Errorf("could not load E2PAL: %s", err.Error())
		}
	} else {
		have_it := false

		if Options.palette != "" && HasExtension(Options.palette, "wad") {
			err = PaletteLoadFromWad(Options.palette, "E2PAL")
			have_it = (err == nil)
		}

		if !have_it {
			// fallback: use the built-in copy
			Warning("   E2END: cannot find E2PAL palette, using built-in")
			PaletteSetHereticE2PAL()
		}
	}

	filename := EncodeLumpName(dirname, lump.Name, "png", false, 0, 0)

	err = RAWPIX_Save(filename, data, W, H)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractHexenSTARTUP(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "png", false, 0, 0)

	err = HexenSTARTUP_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractAnimatedDef(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "txt", false, 0, 0)

	err = ANIMATED_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}

func ExtractSwitchesDef(wd2 *WadExtra, lump *LumpExtra, dirname string) error {
	data, err := wd2.ReadLump(lump.Lump)
	if err != nil {
		return err
	}

	filename := EncodeLumpName(dirname, lump.Name, "txt", false, 0, 0)

	err = SWITCHES_Save(filename, data)
	if err != nil {
		return err
	}

	Verbose("   Saved %-8s to %s", lump.Name, filename)
	return Ok
}
