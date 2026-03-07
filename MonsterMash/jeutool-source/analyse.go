// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "fmt"
import "path/filepath"
import "strings"

import "gitlab.com/andwj/wad"

func CmdInfo(names []string) error {
	if len(names) == 0 {
		return fmt.Errorf("missing filename for info command")
	}

	// determine longest name
	width := 1
	for _, filename := range names {
		base := filepath.Base(filename)
		width = Max(width, len(base))
	}

	for _, filename := range names {
		base := filepath.Base(filename)
		s := InfoStringForWad(filename)
		Message("%-*s : %s", width, base, s)
	}

	return Ok
}

func InfoStringForWad(filename string) string {
	err := ValidateWadFilename(filename)
	if err != nil {
		return err.Error()
	}

	w, err := wad.Open(filename)
	if err != nil {
		return err.Error()
	}

	defer w.Close()

	kind := "PWAD"
	if w.Iwad {
		kind = "IWAD"
	}

	num_lumps := len(w.Directory)

	return fmt.Sprintf("%s with %d lumps", kind, num_lumps)
}

//----------------------------------------------------------------------

func CmdList(names []string) error {
	if len(names) == 0 {
		return fmt.Errorf("missing filename for list command")
	} else if len(names) > 1 {
		return fmt.Errorf("too many filenames")
	}

	filename := names[0]

	err := ValidateWadFilename(filename)
	if err != nil {
		return err
	}

	w, err := wad.Open(filename)
	if err != nil {
		// the error already has the filename, so we don't wrap it
		return err
	}

	defer w.Close()

	wd2 := AnalyseWadDir(w)

	for idx, lump := range wd2.lumps {
		err := IdentifyLump(wd2, lump)

		if err != nil {
			Message("%4d:  %-8s   Error: %s", idx, lump.Name, err.Error())
			continue
		}

		format_str := ""

		if lump.LevelMarker == wad.FORMAT_Doom {
			format_str = "Level header (DOOM format)"
		} else if lump.LevelMarker == wad.FORMAT_Hexen {
			format_str = "Level header (HEXEN format)"
		} else if lump.LevelMarker == wad.FORMAT_UDMF {
			format_str = "Level header (UDMF format)"
		} else if lump.LevelPart {
			format_str = "Level data"
		} else if lump.format == FMT_UNKNOWN && lump.namespace != NS_UNKNOWN {
			format_str = lump.namespace.String() + " data"
		} else {
			format_str = lump.format.String()
		}

		Message("%4d:  %-8s %8d  at 0x%08x  %s", idx, lump.Name,
			lump.Length, lump.Start, format_str)
	}

	return Ok
}

//----------------------------------------------------------------------

type Namespace int

const (
	// Note that some of these are not true WAD namespaces, but
	// just represent sub-directories where we store particular
	// kinds of lumps.

	// Note too that the order is significant (when building),
	// in particular the last three are for consistency with the
	// IWADs (where flats are nearly always last).

	NS_UNKNOWN Namespace = iota

	NS_Special
	NS_Definition

	NS_Demo
	NS_Graphic
	NS_Music
	NS_Sound
	NS_PC_Spkr
	NS_Dialog
	NS_Model
	NS_Level

	NS_Colormap // C_START .. C_END (Boom)
	NS_Trans    // T_START .. T_END (Eternity)
	NS_Voice    // V_START .. V_END (Strife)
	NS_ACS      // A_START .. A_END (ZDoom)
	NS_Hires    // HI_START .. HI_END (ZDoom)
	NS_TX_Tex   // TX_START .. TX_END (ZDoom)
	NS_Voxel    // VX_START .. VX_END (ZDoom)

	NS_Font_A  // FONTA_S .. FONTA_E (Heretic and Hexen)
	NS_Font_AY // FONTAY_S .. FONTAY_E (Hexen)
	NS_Font_B  // FONTB_S .. FONTB_E (Heretic and Hexen)

	NS_Sprite // S_START .. S_END
	NS_Patch  // P_START .. P_END
	NS_Flat   // F_START .. F_END
)

const _NS_FIRST = NS_UNKNOWN
const _NS_LAST = NS_Flat

func (ns Namespace) String() string {
	switch ns {
	case NS_Special:
		return "Special"
	case NS_Definition:
		return "Definition"
	case NS_Level:
		return "Map"
	case NS_Graphic:
		return "Graphic"
	case NS_Sound:
		return "Sound"
	case NS_PC_Spkr:
		return "PC Speaker"
	case NS_Music:
		return "Music"
	case NS_Demo:
		return "Demo"
	case NS_Dialog:
		return "Dialog"
	case NS_Model:
		return "3D Model"

	case NS_Sprite:
		return "Sprite"
	case NS_Flat:
		return "Flat"
	case NS_Patch:
		return "Patch"
	case NS_Colormap:
		return "Colormap"
	case NS_Trans:
		return "Translation"
	case NS_Voice:
		return "Voice"
	case NS_ACS:
		return "ACS"
	case NS_Hires:
		return "Hires"
	case NS_TX_Tex:
		return "Texture"
	case NS_Voxel:
		return "Voxels"
	case NS_Font_A, NS_Font_AY, NS_Font_B:
		return "Font"
	default:
		return "Unknown"
	}
}
func (ns Namespace) DirName() string {
	switch ns {
	case NS_UNKNOWN:
		return "unknown"
	case NS_Special:
		return "special"
	case NS_Definition:
		return "defs"

	case NS_Level:
		return "maps"
	case NS_Graphic:
		return "graphics"
	case NS_Sound:
		return "sounds"
	case NS_PC_Spkr:
		return "pcsfx"
	case NS_Music:
		return "music"
	case NS_Demo:
		return "demos"
	case NS_Dialog:
		return "dialogs"
	case NS_Model:
		return "models"

	case NS_Sprite:
		return "sprites"
	case NS_Flat:
		return "flats"
	case NS_Patch:
		return "patches"
	case NS_Colormap:
		return "colormaps"
	case NS_Trans:
		return "translations"
	case NS_Voice:
		return "voices"
	case NS_ACS:
		return "acs"
	case NS_Hires:
		return "hires"
	case NS_TX_Tex:
		return "textures"
	case NS_Voxel:
		return "voxels"
	case NS_Font_A:
		return "font_a"
	case NS_Font_AY:
		return "font_ay"
	case NS_Font_B:
		return "font_b"
	default:
		panic("missing DirName for namespace")
	}
}

func (ns Namespace) Letter() string {
	switch ns {
	case NS_Sprite:
		return "S"
	case NS_Flat:
		return "F"
	case NS_Patch:
		return "P"
	case NS_Colormap:
		return "C"
	case NS_Trans:
		return "T"
	case NS_Voice:
		return "V"
	case NS_ACS:
		return "A"
	case NS_Hires:
		return "HI"
	case NS_TX_Tex:
		return "TX"
	case NS_Voxel:
		return "VX"
	default:
		return "" // none
	}
}

type LumpExtra struct {
	*wad.Lump

	// the lump's index into the Directory[] array
	index int

	namespace Namespace
	format    FileFormat

	handled bool // already processed?
}

type WadExtra struct {
	*wad.Wad

	lumps []*LumpExtra
}

func AnalyseWadDir(w *wad.Wad) *WadExtra {
	wd2 := new(WadExtra)
	wd2.Wad = w

	wd2.lumps = make([]*LumpExtra, len(w.Directory))

	for i, base := range wd2.Directory {
		lump := new(LumpExtra)
		lump.Lump = base
		lump.index = i

		wd2.lumps[i] = lump

		// mark levels with the NS_Level namespace
		if lump.LevelMarker != wad.NOT_A_LEVEL || lump.LevelPart {
			wd2.lumps[i].namespace = NS_Level
		}
	}

	// most important namespaces done first, override later ones
	wd2.MarkNamespace("S", NS_Sprite)
	wd2.MarkNamespace("F", NS_Flat)
	wd2.MarkNamespace("P", NS_Patch)

	wd2.MarkNamespace("FONTA", NS_Font_A)
	wd2.MarkNamespace("FONTAY", NS_Font_AY)
	wd2.MarkNamespace("FONTB", NS_Font_B)

	wd2.MarkNamespace("C", NS_Colormap)
	wd2.MarkNamespace("T", NS_Trans)
	wd2.MarkNamespace("V", NS_Voice)
	wd2.MarkNamespace("A", NS_ACS)

	wd2.MarkNamespace("HI", NS_Hires)
	wd2.MarkNamespace("TX", NS_TX_Tex)
	wd2.MarkNamespace("VX", NS_Voxel)

	return wd2
}

func (wd2 *WadExtra) MarkNamespace(letter string, ns Namespace) {
	S1_marker := letter + "_START"
	E1_marker := letter + "_END"

	if len(letter) >= 4 {
		S1_marker = letter + "_S"
		E1_marker = letter + "_E"
	}

	S2_marker := S1_marker
	E2_marker := E1_marker

	if len(letter) == 1 {
		S2_marker = letter + letter + "_START"
		E2_marker = letter + letter + "_END"
	}

	s_lump := -1
	e_lump := -1

	for i, lump := range wd2.lumps {
		if lump.Name == S1_marker || lump.Name == S2_marker {
			s_lump = i
		}
		if lump.Name == E1_marker || lump.Name == E2_marker {
			e_lump = i
		}
	}

	if s_lump < 0 && e_lump < 0 {
		return
	}

	if s_lump < 0 {
		Warning("   %s found without matching %s", S1_marker, E1_marker)
		return
	}
	if e_lump < 0 {
		Warning("   %s found without matching %s", E1_marker, S1_marker)
		return
	}
	if s_lump > e_lump {
		Warning("   %s and %s occur in wrong order", S1_marker, E1_marker)
		return
	}

	wd2.lumps[s_lump].format = FMT_MARKER
	wd2.lumps[e_lump].format = FMT_MARKER

	var overlap Namespace

	for i := s_lump + 1; i < e_lump; i++ {
		lump := wd2.lumps[i]

		// ignore maps
		if lump.LevelMarker != wad.NOT_A_LEVEL {
			// warning ??
			Warning("   level %s is inside %s namespace", lump.Name, ns.String())
			continue
		}
		if lump.LevelPart {
			continue
		}

		// ignore existing namespaces
		if lump.namespace != NS_UNKNOWN {
			overlap = lump.namespace
			continue
		}

		lump.namespace = ns
	}

	if overlap != NS_UNKNOWN {
		Warning("   two namespaces overlap (%s + %s)",
			overlap.String(), ns.String())
	}
}

//----------------------------------------------------------------------

type FileFormat int

const (
	FMT_UNKNOWN FileFormat = iota

	// image formats

	FMT_PATCH
	FMT_FLAT
	FMT_RAW_PIX

	FMT_PNG
	FMT_JPEG
	FMT_GIF
	FMT_PCX
	FMT_TGA
	FMT_DDS
	FMT_IMGZ // (ZDoom)

	// sound formats

	FMT_DMX_SND
	FMT_WAV
	FMT_FLAC
	FMT_AIFF
	FMT_VOC
	FMT_VORBIS
	FMT_MP3

	// music formats

	FMT_DMX_MUS
	FMT_MIDI

	// model formats

	FMT_MDL
	FMT_MD2
	FMT_MD3
	FMT_DMD

	// voxel formats

	FMT_KVX

	// other formats

	FMT_TEXT     // text formats (DMXGUS, numerous source port lumps)
	FMT_ANSI     // an ANSI text screen (80x25 with 16 colors)
	FMT_COLORMAP // a color-mapping table (256 or 8704 bytes)
	FMT_DIALOG   // a strife dialog script
	FMT_MARKER   // a marker like S_START or S_END
	FMT_JUNK     // something fairly useless
)

func (form FileFormat) String() string {
	switch form {
	case FMT_PATCH:
		return "DOOM patch image"
	case FMT_FLAT:
		return "DOOM flat image"
	case FMT_RAW_PIX:
		return "Raw pixel image"
	case FMT_PNG:
		return "PNG image"
	case FMT_JPEG:
		return "JPEG image"
	case FMT_GIF:
		return "GIF image"
	case FMT_PCX:
		return "PCX image"
	case FMT_TGA:
		return "TGA image"
	case FMT_DDS:
		return "DDS image"
	case FMT_IMGZ:
		return "ZDoom IMGZ image"

	case FMT_DMX_SND:
		return "DMX audio"
	case FMT_WAV:
		return "WAV audio"
	case FMT_FLAC:
		return "FLAC audio"
	case FMT_AIFF:
		return "AIFF audio"
	case FMT_VOC:
		return "VOC audio"
	case FMT_VORBIS:
		return "Ogg/Vorbis audio"
	case FMT_MP3:
		return "MP3 audio"

	case FMT_DMX_MUS:
		return "DMX (MUS) music"
	case FMT_MIDI:
		return "MIDI music"

	case FMT_MDL:
		return "MDL 3D model"
	case FMT_MD2:
		return "MD2 3D model"
	case FMT_MD3:
		return "MD3 3D model"
	case FMT_DMD:
		return "DMD 3D model"

	case FMT_TEXT:
		return "Text lump"
	case FMT_KVX:
		return "Voxel model"
	case FMT_ANSI:
		return "ANSI text screen"
	case FMT_DIALOG:
		return "Dialog script (compiled)"
	case FMT_COLORMAP:
		return "Color mapping"
	case FMT_MARKER:
		return "Marker"
	case FMT_JUNK:
		return "Junk"

	default:
		return "????"
	}
}

func (form FileFormat) Extension() string {
	switch form {
	case FMT_PNG:
		return "png"
	case FMT_JPEG:
		return "jpeg"
	case FMT_GIF:
		return "gif"
	case FMT_PCX:
		return "pcx"
	case FMT_TGA:
		return "tga"
	case FMT_DDS:
		return "dds"
	case FMT_IMGZ:
		return "imgz"

	case FMT_WAV:
		return "wav"
	case FMT_FLAC:
		return "flac"
	case FMT_AIFF:
		return "aiff"
	case FMT_VOC:
		return "voc"
	case FMT_VORBIS:
		return "ogg"
	case FMT_MP3:
		return "mp3"

	case FMT_DMX_MUS:
		return "mus"
	case FMT_MIDI:
		return "midi"

	case FMT_MDL:
		return "mdl"
	case FMT_MD2:
		return "md2"
	case FMT_MD3:
		return "md3"
	case FMT_DMD:
		return "dmd"

	case FMT_TEXT:
		return "txt"
	case FMT_DIALOG:
		return "o"

	// everything else will need special handling!
	default:
		return ""
	}
}

func IdentifyLump(wd2 *WadExtra, lump *LumpExtra) error {
	// read some data at beginning of the lump, so we can detect
	// different formats (by looking for "magic" bytes).
	buf, err := wd2.ReadLumpPartial(lump.Lump, 16384)
	if err != nil {
		return err
	}

	// already determined?
	if lump.format != FMT_UNKNOWN {
		return Ok
	}

	// zero length lumps are generally markers or junk
	// (a notable exception is lumps within a level)
	if lump.Length == 0 {
		if lump.namespace == NS_Level {
			return Ok
		}

		if strings.HasSuffix(lump.Name, "_START") ||
			strings.HasSuffix(lump.Name, "_END") {
			lump.format = FMT_MARKER
		} else {
			lump.format = FMT_JUNK
		}
		return Ok
	}

	/* first part: handle known namespaces */

	ns := lump.namespace

	if ns == NS_Level {
		return Ok
	}

	if ns == NS_Flat {
		if !IdentifyImage(lump, buf) {
			lump.format = FMT_FLAT
		}
		return Ok
	}

	if ns == NS_Sprite || ns == NS_Patch ||
		ns == NS_TX_Tex || ns == NS_Hires ||
		ns == NS_Font_A || ns == NS_Font_AY ||
		ns == NS_Font_B {

		if IdentifyImage(lump, buf) {
			return Ok
		}
		IdentifyPatchLump(lump, buf)
		return Ok
	}

	if ns == NS_Colormap || ns == NS_Trans {
		lump.format = FMT_COLORMAP
		return Ok
	}

	if ns == NS_Voice {
		if IdentifySound(lump, buf) {
			return Ok
		}
		// look for MP3 etc
		IdentifyMusic(lump, buf)
		return Ok
	}

	if ns == NS_ACS {
		// need anything here ??
		return Ok
	}

	if ns == NS_Voxel {
		// this is just an assumption
		lump.format = FMT_KVX
		return Ok
	}

	/* second part: handle NS_UNKNOWN, and determine namespace */

	if IdentifyLumpByName(lump, buf) {
		// the function set the namespace too
		return Ok
	}

	if IdentifyImage(lump, buf) {
		lump.namespace = NS_Graphic
		return Ok
	}

	if Identify3DModel(lump, buf) {
		lump.namespace = NS_Model
		return Ok
	}

	if IdentifyMusic(lump, buf) {
		lump.namespace = NS_Music
		return Ok
	}

	if IdentifySound(lump, buf) {
		lump.namespace = NS_Sound
		return Ok
	}

	if IdentifyPCSpeaker(lump, buf) {
		lump.namespace = NS_PC_Spkr
		return Ok
	}

	// Heretic, Hexen and Strife use raw pixel blocks for a few things
	if IdentifyRawPixels(lump, buf) {
		lump.namespace = NS_Special
		return Ok
	}

	if IdentifyPatchLump(lump, buf) {
		lump.namespace = NS_Graphic
		return Ok
	}

	if IdentifyTextLump(buf) {
		lump.format = FMT_TEXT
		lump.namespace = NS_Definition
		return Ok
	}

	// TODO: should we identify flats outside of their namespace?

	// leave format and namespace as UNKNOWN
	return Ok
}

func IdentifyImage(lump *LumpExtra, buf []byte) bool {
	if lump.Length > 7 &&
		buf[0] == 0x89 &&
		buf[1] == 'P' && buf[2] == 'N' && buf[3] == 'G' &&
		buf[4] == 0x0D && buf[5] == 0x0A && buf[6] == 0x1A {

		lump.format = FMT_PNG
		return true
	}

	if lump.Length > 7 &&
		buf[0] == 0xFF && buf[1] == 0xD8 &&
		buf[2] == 0xFF && buf[3] >= 0xE0 &&
		((buf[6] == 'J' && buf[7] == 'F') ||
			(buf[6] == 'E' && buf[7] == 'x')) {

		lump.format = FMT_JPEG
		return true
	}

	if lump.Length > 7 &&
		buf[0] == 'G' && buf[1] == 'I' && buf[2] == 'F' &&
		buf[3] == '8' && buf[4] >= '7' && buf[4] <= '9' &&
		buf[5] == 'a' {

		lump.format = FMT_GIF
		return true
	}

	if lump.Length > 124 &&
		buf[0] == 'D' && buf[1] == 'D' &&
		buf[2] == 'S' && buf[3] == 0x20 &&
		buf[4] == 124 && buf[5] == 0 && buf[6] == 0 {

		lump.format = FMT_DDS
		return true
	}

	if lump.Length > 24 &&
		buf[0] == 'I' && buf[1] == 'M' &&
		buf[2] == 'G' && buf[3] == 'Z' &&
		buf[12] < 2 && buf[13] == 0 {

		lump.format = FMT_IMGZ
		return true
	}

	if lump.Length > 128 &&
		buf[0] == 10 && buf[1] == 5 &&
		buf[2] == 1 && buf[3] == 8 &&
		buf[5] < 16 && buf[7] < 16 &&
		buf[64] == 0 &&
		(buf[65] == 1 || buf[65] == 3) {

		lump.format = FMT_PCX
		return true
	}

	if lump.Length > 18 &&
		((buf[1] == 0 && (buf[2] == 2 || buf[2] == 3 || buf[2] == 10)) ||
			(buf[1] == 1 && (buf[2] == 1 || buf[2] == 9))) &&
		(buf[7] == buf[1]*24 || buf[7] == buf[1]*32) &&
		(buf[16] == 8 || buf[16] == 24 || buf[16] == 32) &&
		buf[6] < 2 &&
		buf[9] == 0 && buf[11] == 0 &&
		buf[13] <= 16 && buf[15] <= 8 {

		lump.format = FMT_TGA
		return true
	}

	return false
}

func IdentifyMusic(lump *LumpExtra, buf []byte) bool {
	// TODO : it is possible for MP3 or OGG to be used as sounds, or for
	//        WAV (etc) to be used for music -- try to be smarter.

	if lump.Length > 7 &&
		buf[0] == 'M' && buf[1] == 'U' &&
		buf[2] == 'S' && buf[3] == 0x1A &&
		buf[9] == 0 {

		lump.format = FMT_DMX_MUS
		return true
	}

	if lump.Length > 7 &&
		buf[0] == 'M' && buf[1] == 'T' &&
		buf[2] == 'h' && buf[3] == 'd' &&
		buf[4] == 0 && buf[5] == 0 && buf[6] == 0 {

		lump.format = FMT_MIDI
		return true
	}

	if lump.Length > 7 &&
		buf[0] == 'O' && buf[1] == 'g' &&
		buf[2] == 'g' && buf[3] == 'S' &&
		buf[4] == 0 {

		lump.format = FMT_VORBIS
		return true
	}

	// MP3 with a prefixed ID3v2 tag
	if lump.Length > 10 &&
		buf[0] == 'I' && buf[1] == 'D' && buf[2] == '3' &&
		buf[3] < 6 && buf[4] < 10 &&
		(buf[5]&7) == 0 && buf[6] == 0 {

		lump.format = FMT_MP3
		return true
	}

	// MP3 without a tag [ rather ambiguous ]
	if lump.Length > 1000 &&
		buf[0] == 0xff && buf[1] == 0xfb &&
		buf[4] == 0 && buf[5] == 0 && buf[6] < 31 {

		lump.format = FMT_MP3
		return true
	}

	return false
}

func IdentifySound(lump *LumpExtra, buf []byte) bool {
	if lump.Length > 15 &&
		buf[0] == 'R' && buf[1] == 'I' &&
		buf[2] == 'F' && buf[3] == 'F' &&
		buf[7] < 32 &&
		buf[8] == 'W' && buf[9] == 'A' &&
		buf[10] == 'V' && buf[11] == 'E' {

		lump.format = FMT_WAV
		return true
	}

	if lump.Length > 10 &&
		buf[0] == 'f' && buf[1] == 'L' &&
		buf[2] == 'a' && buf[3] == 'C' &&
		buf[5] == 0 && buf[6] == 0 {

		lump.format = FMT_FLAC
		return true
	}

	if lump.Length > 15 &&
		buf[0] == 'F' && buf[1] == 'O' &&
		buf[2] == 'R' && buf[3] == 'M' &&
		buf[4] < 32 &&
		buf[8] == 'A' && buf[9] == 'I' &&
		buf[10] == 'F' && buf[11] == 'F' {

		lump.format = FMT_AIFF
		return true
	}

	if lump.Length > 10 &&
		buf[0] == 'C' && buf[1] == 'r' && buf[2] == 'e' &&
		buf[9] == 'V' && buf[10] == 'o' && buf[11] == 'i' &&
		buf[19] == 0x1A && buf[21] == 0 {

		lump.format = FMT_VOC
		return true
	}

	// the DMX sound format is difficult to distinguish from a
	// narrow PATCH image.  since the samples are 8-bit and mono,
	// we can check that the number of samples roughly matches the
	// size of the lump.

	if lump.Length > 8 &&
		buf[0] == 3 && buf[1] == 0 &&
		buf[3] > 10 && buf[7] == 0 {

		samples := RawLong(buf[4:])

		if lump.Length-16 <= samples && samples < lump.Length {
			lump.format = FMT_DMX_SND
			return true
		}
	}

	return false
}

func IdentifyPCSpeaker(lump *LumpExtra, buf []byte) bool {
	name := lump.Name

	// the PC speaker format is has very little to recognise it,
	// mainly a 4 byte header containing the number of notes to play.
	// luckily the lump names always begin with "DP".

	// TODO : check the length too

	if len(name) > 2 && lump.Length >= 4 &&
		name[0] == 'D' && name[1] == 'P' &&
		buf[0] == 0 && buf[1] == 0 {

		return true
	}

	return false
}

func IdentifyLumpByName(lump *LumpExtra, buf []byte) bool {
	// NOTE: this only handles *binary* lumps.  Most of the features
	// of source-ports, such as DECORATE, use text lumps and these
	// will be detected normally (as FMT_TEXT lumps).

	name := lump.Name

	// colormaps, including ones like FOGMAP in Hexen
	if name == "COLORMAP" ||
		(lump.Length == 34*256 && strings.HasSuffix(name, "MAP")) {

		lump.format = FMT_COLORMAP
		lump.namespace = NS_Special
		return true
	}

	// demos
	switch name {
	case "DEMO1", "DEMO2", "DEMO3", "DEMO4":
		lump.namespace = NS_Demo
		return true
	}

	// ANSI text screens
	switch name {
	case "ENDOOM", "ENDBOOM", "ENDTEXT", "ENDSTRF", "LOADING":
		lump.format = FMT_ANSI
		lump.namespace = NS_Special
		return true
	}

	// color translation tables
	if name == "TRANMAP" /* Boom */ ||
		name == "TINTTAB" /* Heretic and Hexen */ ||
		name == "XLATAB" /* Strife */ ||
		strings.HasPrefix(name, "TRANTBL") /* Hexen */ {

		lump.format = FMT_COLORMAP
		lump.namespace = NS_Special
		return true
	}

	// Strife dialogs (compiled)
	if "SCRIPT00" <= name && name <= "SCRIPT99" {
		lump.format = FMT_DIALOG
		lump.namespace = NS_Dialog
		return true
	}
	// DIALOGxx seems to be a ZDoom-ism, script is plain text
	if "DIALOG00" <= name && name <= "DIALOG99" {
		lump.format = FMT_TEXT
		lump.namespace = NS_Dialog
		return true
	}

	// Hexen's STARTUP lump is a 4-bit format.
	// There are two "notch" images associated with it, they are
	// hard-coded in vanilla but ZDoom supports them as lumps.
	if name == "STARTUP" && lump.Length == (640*480/2+16*3) {
		lump.namespace = NS_Special
		return true
	}
	if name == "NOTCH" || name == "NETNOTCH" {
		lump.namespace = NS_Special
		return true
	}

	switch name {
	case
		// common stuff
		"PLAYPAL",
		"GENMIDI",
		"PNAMES",
		"TEXTURE1",
		"TEXTURE2",

		// Heretic and Hexen
		"E2END",
		"E2PAL",
		"SNDCURVE",

		// Boom
		"SWITCHES",
		"ANIMATED":

		lump.namespace = NS_Special
		return true
	}

	// some things are best ignored
	switch name {
	case "__EUREKA", "_DEUTEX_", "GFRAG", "XXTIC":
		lump.format = FMT_JUNK
		return true
	}

	return false
}

func IdentifyTextLump(buf []byte) bool {
	if len(buf) == 0 {
		return false
	}

	// allow a single trailing NUL byte
	// [ this occurs in some Strife lumps ]
	if len(buf) >= 2 && buf[len(buf)-1] == 0 {
		buf = buf[0 : len(buf)-1]
	}

	// this logic is not 100% reliable (which may be impossible).
	// it is more likely to wrongly mark a binary lump as text than
	// vice versa.

	// it assumes several things:
	// -  zero bytes never occur in text (nearly always true)
	//
	// -  bytes > 0xf5 are invalid in text (for ASCII and UTF-8, that
	//    is true, but not for other charsets)
	//
	// -  bytes < 8 and some other ones < 32 are control characters and
	//    never occur in text files (generally true, but not always).

	for _, b := range buf {
		if b < 8 || b > 0xf5 ||
			(b >= 14 && b <= 25) ||
			(b >= 28 && b <= 31) {
			return false
		}
	}

	return true
}

func IdentifyPatchLump(lump *LumpExtra, buf []byte) bool {
	if lump.Length < 8 {
		return false
	}

	// width and height (they can never be negative)
	W := int(RawWord(buf[0:]))
	H := int(RawWord(buf[2:]))

	if W > 4096 || H > 2048 {
		return false
	}

	// I assume zero-sized patches are not a thing
	if W == 0 || H == 0 {
		return false
	}

	// left and top offset (can be negative)
	L := int(int16(RawWord(buf[4:])))
	T := int(int16(RawWord(buf[6:])))

	if Abs(L) > 4096 || Abs(T) > 2048 {
		return false
	}

	if int(lump.Length) < 8+W*4 {
		return false
	}

	// verify that the column offsets are valid
	for i := 0; i < W; i++ {
		ofs := RawLong(buf[8+i*4:])

		if ofs < 8 || ofs >= lump.Length {
			return false
		}
	}

	lump.format = FMT_PATCH
	return true
}

func IdentifyRawPixels(lump *LumpExtra, buf []byte) bool {
	// most common usage is for full-screen pictures
	if lump.Length == 320*200 {
		lump.format = FMT_RAW_PIX
		return true
	}

	switch lump.Name {
	// Heretic and Hexen
	case "AUTOPAGE":
		lump.format = FMT_RAW_PIX
		return true

	// Strife
	case "STARTUP0", "STRTLZ1", "STRTLZ2", "STRTBOT":
		lump.format = FMT_RAW_PIX
		return true

	case "STRTPA1", "STRTPB1", "STRTPC1", "STRTPD1":
		lump.format = FMT_RAW_PIX
		return true
	}

	return false
}

func Identify3DModel(lump *LumpExtra, buf []byte) bool {
	if len(buf) < 50 {
		return false
	}

	if buf[0] == 'I' && buf[1] == 'D' &&
		buf[2] == 'P' && buf[3] == 'O' &&
		RawLong(buf[4:]) < 32 {

		// this is Quake's original format
		lump.format = FMT_MDL
		return true
	}

	if buf[0] == 'I' && buf[1] == 'D' &&
		buf[2] == 'S' && buf[3] == 'T' &&
		RawLong(buf[4:]) < 32 {

		// this is the format from Half-Life
		lump.format = FMT_MDL
		return true
	}

	if buf[0] == 'I' && buf[1] == 'D' &&
		buf[2] == 'P' && buf[3] == '2' &&
		RawLong(buf[4:]) < 32 {

		lump.format = FMT_MD2
		return true
	}

	if buf[0] == 'I' && buf[1] == 'D' &&
		buf[2] == 'P' && buf[3] == '3' &&
		RawLong(buf[4:]) < 33 {

		lump.format = FMT_MD3
		return true
	}

	if buf[0] == 'D' && buf[1] == 'M' &&
		buf[2] == 'D' && buf[3] == 'M' &&
		RawLong(buf[4:]) < 32 {

		// a format created for the Doomsday engine
		lump.format = FMT_DMD
		return true
	}

	// TODO: detect the Unreal ".3d" format

	return false
}
