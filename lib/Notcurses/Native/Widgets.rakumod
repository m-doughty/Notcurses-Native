use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Widgets;

# 124 bindings — all widget subsystems

# === Reel (scrollable tablet container) ===

sub ncreel_create(NcplaneHandle $n, NcreelOptions $popts --> NcreelHandle)
	is native($core-lib) is export { * }

sub ncreel_plane(NcreelHandle $nr --> NcplaneHandle)
	is native($core-lib) is export { * }

# after/before are nctablet*, cb is tabletcb, opaque is void*; returns nctablet*
sub ncreel_add(NcreelHandle $nr, Pointer $after, Pointer $before, Pointer $cb, Pointer $opaque --> Pointer)
	is native($core-lib) is export { * }

sub ncreel_tabletcount(NcreelHandle $nr --> int32)
	is native($core-lib) is export { * }

# t is nctablet*
sub ncreel_del(NcreelHandle $nr, Pointer $t --> int32)
	is native($core-lib) is export { * }

sub ncreel_redraw(NcreelHandle $nr --> int32)
	is native($core-lib) is export { * }

sub ncreel_offer_input(NcreelHandle $nr, Ncinput $ni --> bool)
	is native($core-lib) is export { * }

# Returns nctablet*
sub ncreel_focused(NcreelHandle $nr --> Pointer)
	is native($core-lib) is export { * }

sub ncreel_next(NcreelHandle $nr --> Pointer)
	is native($core-lib) is export { * }

sub ncreel_prev(NcreelHandle $nr --> Pointer)
	is native($core-lib) is export { * }

sub ncreel_destroy(NcreelHandle $nr)
	is native($core-lib) is export { * }

# nctablet accessors (tablet is opaque Pointer)
sub nctablet_userptr(Pointer $t --> Pointer)
	is native($core-lib) is export { * }

sub nctablet_plane(Pointer $t --> NcplaneHandle)
	is native($core-lib) is export { * }

# === Selector (single-item picker) ===

sub ncselector_create(NcplaneHandle $n, NcselectorOptions $opts --> NcselectorHandle)
	is native($core-lib) is export { * }

sub ncselector_additem(NcselectorHandle $n, NcselectorItem $item --> int32)
	is native($core-lib) is export { * }

sub ncselector_delitem(NcselectorHandle $n, Str $item --> int32)
	is native($core-lib) is export { * }

sub ncselector_selected(NcselectorHandle $n --> Str)
	is native($core-lib) is export { * }

sub ncselector_plane(NcselectorHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncselector_previtem(NcselectorHandle $n --> Str)
	is native($core-lib) is export { * }

sub ncselector_nextitem(NcselectorHandle $n --> Str)
	is native($core-lib) is export { * }

sub ncselector_offer_input(NcselectorHandle $n, Ncinput $nc --> bool)
	is native($core-lib) is export { * }

# item is char** output (pass Pointer for NULL or to receive selected item string)
sub ncselector_destroy(NcselectorHandle $n, Pointer $item)
	is native($core-lib) is export { * }

# === Multiselector (multi-item picker) ===

sub ncmultiselector_create(NcplaneHandle $n, NcmultiselectorOptions $opts --> NcmultiselectorHandle)
	is native($core-lib) is export { * }

# selected is bool* array output
sub ncmultiselector_selected(NcmultiselectorHandle $n, Pointer $selected, uint32 $count --> int32)
	is native($core-lib) is export { * }

sub ncmultiselector_plane(NcmultiselectorHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncmultiselector_offer_input(NcmultiselectorHandle $n, Ncinput $nc --> bool)
	is native($core-lib) is export { * }

sub ncmultiselector_destroy(NcmultiselectorHandle $n)
	is native($core-lib) is export { * }

# === Tree ===

sub nctree_create(NcplaneHandle $n, NctreeOptions $opts --> NctreeHandle)
	is native($core-lib) is export { * }

sub nctree_plane(NctreeHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub nctree_redraw(NctreeHandle $n --> int32)
	is native($core-lib) is export { * }

sub nctree_offer_input(NctreeHandle $n, Ncinput $ni --> bool)
	is native($core-lib) is export { * }

# Returns void* (user data of focused item)
sub nctree_focused(NctreeHandle $n --> Pointer)
	is native($core-lib) is export { * }

sub nctree_next(NctreeHandle $n --> Pointer)
	is native($core-lib) is export { * }

sub nctree_prev(NctreeHandle $n --> Pointer)
	is native($core-lib) is export { * }

# spec is const unsigned* path array, failspec is int* output
sub nctree_goto(NctreeHandle $n, CArray[uint32] $spec, int32 $failspec is rw --> Pointer)
	is native($core-lib) is export { * }

# spec is const unsigned*, add is nctree_item*
sub nctree_add(NctreeHandle $n, CArray[uint32] $spec, Pointer $add --> int32)
	is native($core-lib) is export { * }

sub nctree_del(NctreeHandle $n, CArray[uint32] $spec --> int32)
	is native($core-lib) is export { * }

sub nctree_destroy(NctreeHandle $n)
	is native($core-lib) is export { * }

# === Menu ===

sub ncmenu_create(NcplaneHandle $n, NcmenuOptions $opts --> NcmenuHandle)
	is native($core-lib) is export { * }

sub ncmenu_unroll(NcmenuHandle $n, int32 $sectionidx --> int32)
	is native($core-lib) is export { * }

sub ncmenu_rollup(NcmenuHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncmenu_nextsection(NcmenuHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncmenu_prevsection(NcmenuHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncmenu_nextitem(NcmenuHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncmenu_previtem(NcmenuHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncmenu_item_set_status(NcmenuHandle $n, Str $section, Str $item, bool $enabled --> int32)
	is native($core-lib) is export { * }

sub ncmenu_selected(NcmenuHandle $n, Ncinput $ni --> Str)
	is native($core-lib) is export { * }

sub ncmenu_mouse_selected(NcmenuHandle $n, Ncinput $click, Ncinput $ni --> Str)
	is native($core-lib) is export { * }

sub ncmenu_plane(NcmenuHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncmenu_offer_input(NcmenuHandle $n, Ncinput $nc --> bool)
	is native($core-lib) is export { * }

sub ncmenu_destroy(NcmenuHandle $n)
	is native($core-lib) is export { * }

# === Progress bar ===

sub ncprogbar_create(NcplaneHandle $n, NcprogbarOptions $opts --> NcprogbarHandle)
	is native($core-lib) is export { * }

sub ncprogbar_plane(NcprogbarHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncprogbar_set_progress(NcprogbarHandle $n, num64 $p --> int32)
	is native($core-lib) is export { * }

sub ncprogbar_progress(NcprogbarHandle $n --> num64)
	is native($core-lib) is export { * }

sub ncprogbar_destroy(NcprogbarHandle $n)
	is native($core-lib) is export { * }

# === Tabbed ===

sub nctabbed_create(NcplaneHandle $n, NctabbedOptions $opts --> NctabbedHandle)
	is native($core-lib) is export { * }

sub nctabbed_destroy(NctabbedHandle $nt)
	is native($core-lib) is export { * }

sub nctabbed_redraw(NctabbedHandle $nt)
	is native($core-lib) is export { * }

sub nctabbed_ensure_selected_header_visible(NctabbedHandle $nt)
	is native($core-lib) is export { * }

sub nctabbed_selected(NctabbedHandle $nt --> NctabHandle)
	is native($core-lib) is export { * }

sub nctabbed_leftmost(NctabbedHandle $nt --> NctabHandle)
	is native($core-lib) is export { * }

sub nctabbed_tabcount(NctabbedHandle $nt --> int32)
	is native($core-lib) is export { * }

sub nctabbed_plane(NctabbedHandle $nt --> NcplaneHandle)
	is native($core-lib) is export { * }

sub nctabbed_content_plane(NctabbedHandle $nt --> NcplaneHandle)
	is native($core-lib) is export { * }

# nctab accessors
sub nctab_cb(NctabHandle $t --> Pointer)
	is native($core-lib) is export { * }

sub nctab_name(NctabHandle $t --> Str)
	is native($core-lib) is export { * }

sub nctab_name_width(NctabHandle $t --> int32)
	is native($core-lib) is export { * }

sub nctab_userptr(NctabHandle $t --> Pointer)
	is native($core-lib) is export { * }

sub nctab_next(NctabHandle $t --> NctabHandle)
	is native($core-lib) is export { * }

sub nctab_prev(NctabHandle $t --> NctabHandle)
	is native($core-lib) is export { * }

# after/before are NctabHandle, tcb is tabcb callback, opaque is void*
sub nctabbed_add(NctabbedHandle $nt, NctabHandle $after, NctabHandle $before, Pointer $tcb, Str $name, Pointer $opaque --> NctabHandle)
	is native($core-lib) is export { * }

sub nctabbed_del(NctabbedHandle $nt, NctabHandle $t --> int32)
	is native($core-lib) is export { * }

sub nctab_move(NctabbedHandle $nt, NctabHandle $t, NctabHandle $after, NctabHandle $before --> int32)
	is native($core-lib) is export { * }

sub nctab_move_right(NctabbedHandle $nt, NctabHandle $t)
	is native($core-lib) is export { * }

sub nctab_move_left(NctabbedHandle $nt, NctabHandle $t)
	is native($core-lib) is export { * }

sub nctabbed_rotate(NctabbedHandle $nt, int32 $amt)
	is native($core-lib) is export { * }

sub nctabbed_next(NctabbedHandle $nt --> NctabHandle)
	is native($core-lib) is export { * }

sub nctabbed_prev(NctabbedHandle $nt --> NctabHandle)
	is native($core-lib) is export { * }

sub nctabbed_select(NctabbedHandle $nt, NctabHandle $t --> NctabHandle)
	is native($core-lib) is export { * }

sub nctabbed_channels(NctabbedHandle $nt, uint64 $hdrchan is rw, uint64 $selchan is rw, uint64 $sepchan is rw)
	is native($core-lib) is export { * }

sub nctabbed_hdrchan(NctabbedHandle $nt --> uint64)
	is native($ffi-lib) is export { * }

sub nctabbed_selchan(NctabbedHandle $nt --> uint64)
	is native($ffi-lib) is export { * }

sub nctabbed_sepchan(NctabbedHandle $nt --> uint64)
	is native($ffi-lib) is export { * }

sub nctabbed_separator(NctabbedHandle $nt --> Str)
	is native($core-lib) is export { * }

sub nctabbed_separator_width(NctabbedHandle $nt --> int32)
	is native($core-lib) is export { * }

sub nctabbed_set_hdrchan(NctabbedHandle $nt, uint64 $chan)
	is native($core-lib) is export { * }

sub nctabbed_set_selchan(NctabbedHandle $nt, uint64 $chan)
	is native($core-lib) is export { * }

sub nctabbed_set_sepchan(NctabbedHandle $nt, uint64 $chan)
	is native($core-lib) is export { * }

# newcb is tabcb callback; returns old callback
sub nctab_set_cb(NctabHandle $t, Pointer $newcb --> Pointer)
	is native($core-lib) is export { * }

sub nctab_set_name(NctabHandle $t, Str $newname --> int32)
	is native($core-lib) is export { * }

sub nctab_set_userptr(NctabHandle $t, Pointer $newopaque --> Pointer)
	is native($core-lib) is export { * }

sub nctabbed_set_separator(NctabbedHandle $nt, Str $separator --> int32)
	is native($core-lib) is export { * }

# === Plot (uint64) ===

sub ncuplot_create(NcplaneHandle $n, NcplotOptions $opts, uint64 $miny, uint64 $maxy --> NcuplotHandle)
	is native($core-lib) is export { * }

sub ncuplot_plane(NcuplotHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncuplot_add_sample(NcuplotHandle $n, uint64 $x, uint64 $y --> int32)
	is native($core-lib) is export { * }

sub ncuplot_set_sample(NcuplotHandle $n, uint64 $x, uint64 $y --> int32)
	is native($core-lib) is export { * }

sub ncuplot_sample(NcuplotHandle $n, uint64 $x, uint64 $y is rw --> int32)
	is native($core-lib) is export { * }

sub ncuplot_destroy(NcuplotHandle $n)
	is native($core-lib) is export { * }

# === Plot (double) ===

sub ncdplot_create(NcplaneHandle $n, NcplotOptions $opts, num64 $miny, num64 $maxy --> NcdplotHandle)
	is native($core-lib) is export { * }

sub ncdplot_plane(NcdplotHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncdplot_add_sample(NcdplotHandle $n, uint64 $x, num64 $y --> int32)
	is native($core-lib) is export { * }

sub ncdplot_set_sample(NcdplotHandle $n, uint64 $x, num64 $y --> int32)
	is native($core-lib) is export { * }

sub ncdplot_sample(NcdplotHandle $n, uint64 $x, num64 $y is rw --> int32)
	is native($core-lib) is export { * }

sub ncdplot_destroy(NcdplotHandle $n)
	is native($core-lib) is export { * }

# === FD plane (async I/O on file descriptors) ===

# cbfxn/donecbfxn are callbacks
sub ncfdplane_create(NcplaneHandle $n, NcfdplaneOptions $opts, int32 $fd, Pointer $cbfxn, Pointer $donecbfxn --> NcfdplaneHandle)
	is native($core-lib) is export { * }

sub ncfdplane_plane(NcfdplaneHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncfdplane_destroy(NcfdplaneHandle $n --> int32)
	is native($core-lib) is export { * }

# === Subprocess ===

# argv is char*const*, cbfxn/donecbfxn are callbacks
sub ncsubproc_createv(NcplaneHandle $n, NcsubprocOptions $opts, Str $bin, Pointer $argv, Pointer $cbfxn, Pointer $donecbfxn --> NcsubprocHandle)
	is native($core-lib) is export { * }

sub ncsubproc_createvp(NcplaneHandle $n, NcsubprocOptions $opts, Str $bin, Pointer $argv, Pointer $cbfxn, Pointer $donecbfxn --> NcsubprocHandle)
	is native($core-lib) is export { * }

# envp is char*const*
sub ncsubproc_createvpe(NcplaneHandle $n, NcsubprocOptions $opts, Str $bin, Pointer $argv, Pointer $envp, Pointer $cbfxn, Pointer $donecbfxn --> NcsubprocHandle)
	is native($core-lib) is export { * }

sub ncsubproc_plane(NcsubprocHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncsubproc_destroy(NcsubprocHandle $n --> int32)
	is native($core-lib) is export { * }

# === Reader (text input) ===

sub ncreader_create(NcplaneHandle $n, NcreaderOptions $opts --> NcreaderHandle)
	is native($core-lib) is export { * }

sub ncreader_clear(NcreaderHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncreader_plane(NcreaderHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncreader_offer_input(NcreaderHandle $n, Ncinput $ni --> bool)
	is native($core-lib) is export { * }

sub ncreader_move_left(NcreaderHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncreader_move_right(NcreaderHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncreader_move_up(NcreaderHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncreader_move_down(NcreaderHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncreader_write_egc(NcreaderHandle $n, Str $egc --> int32)
	is native($core-lib) is export { * }

sub ncreader_contents(NcreaderHandle $n --> Str)
	is native($core-lib) is export { * }

# contents is char** output
sub ncreader_destroy(NcreaderHandle $n, Pointer $contents)
	is native($core-lib) is export { * }
