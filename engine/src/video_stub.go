//go:build novideo

package main

// Stub used for builds without FFmpeg (e.g. the iOS port). Stage/storyboard
// video backgrounds are skipped; everything else keeps working.
type bgVideo struct {
	texture Texture
	muted   bool
}

func (bgv *bgVideo) Open(filename string, volume int, sm BgVideoScaleMode, sf BgVideoScaleFilter, loop bool) error {
	// Succeed silently: the background simply renders nothing (texture stays nil).
	return nil
}
func (bgv *bgVideo) Tick() error        { return nil }
func (bgv *bgVideo) SetPlaying(on bool) {}
func (bgv *bgVideo) SetVisible(on bool) {}
func (bgv *bgVideo) Reset()             {}
func (bgv *bgVideo) updateAudioVolume() {}
func (bgv *bgVideo) MixerCleared()      {}
func (bgv *bgVideo) Close()             {}
