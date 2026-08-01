;;; MeshmoreXR deploy/watch helpers.
;;;
;;; WHY THESE EXIST: the build-install-launch-watch cycle was being retyped as a
;;; ~400-character shell pipeline every time, which is slow to write, easy to get
;;; subtly wrong, and asks for a fresh permission each round because the command
;;; text differs. These make it one call. The shell commands underneath are
;;; unchanged and still work standalone -- nothing is locked behind Pop-11.

vars XR_DIR   = '/Users/dkords/dev/projects/iotj/meshmore-sns.git/meshmore-xr';
vars ADB      = '/Users/dkords/Library/Android/sdk/platform-tools/adb';
vars PKG      = 'com.iotj.meshmore.xr';
vars SCRATCH  = '/private/tmp/claude-501/-Users-dkords-dev-projects-iotj-meshmore-sns-git/66103b82-49aa-4c4b-8572-176e0eda7a60/scratchpad';
vars XR_SERIAL = false;

;;; Collect a shell command's stdout+stderr as a list of strings.
define shell_lines(cmd);
    lvars r = sys_obey_linerep(cmd sys_>< ' 2>&1'), line, acc = [];
    repeat
        r() -> line;
        quitif(line == termin);
        [^^acc ^line] -> acc;
    endrepeat;
    acc
enddefine;

;;; WHICH DEVICE. Two are usually attached -- the phone and the XR puck -- and
;;; installing the glasses build on the phone is a silent no-op that looks like
;;; success. Probe for the spatial feature rather than trusting a serial: a
;;; hardcoded serial is right until the day it is not, and then it is wrong
;;; quietly.
define xr_find_device();
    lvars ss = shell_lines(ADB sys_>< ' devices'), s, serial, feats;
    false -> XR_SERIAL;
    for s in ss do
        if issubstring('\tdevice', 1, s) then
            substring(1, locchar(`\t`, 1, s) - 1, s) -> serial;
            shell_lines(ADB sys_>< ' -s ' sys_>< serial
                        sys_>< ' shell pm list features </dev/null') -> feats;
            lvars f;
            for f in feats do
                if issubstring('xr.api.spatial', 1, f) then
                    serial -> XR_SERIAL;
                    quitloop(2);
                endif;
            endfor;
        endif;
    endfor;
    XR_SERIAL
enddefine;

define need_device();
    unless XR_SERIAL then xr_find_device() -> ; endunless;
    unless XR_SERIAL then
        npr('!! no XR device attached');
        false
    else true
    endunless
enddefine;

define adb(args);
    ADB sys_>< ' -s ' sys_>< XR_SERIAL sys_>< ' ' sys_>< args
enddefine;

;;; BUILD + INSTALL. Returns true on success. On failure it prints the compiler
;;; errors and nothing else -- the 60 lines of Gradle preamble are noise every
;;; single time and actively hide the one line that matters.
define xr_install();
    returnunless(need_device())(false);
    lvars out = shell_lines('cd ' sys_>< XR_DIR
        sys_>< ' && ANDROID_SERIAL=' sys_>< XR_SERIAL sys_>< ' bin/xr install');
    lvars l, ok = false, errs = [];
    for l in out do
        if issubstring('BUILD SUCCESSFUL', 1, l) then true -> ok; endif;
        if issubstring('e: ', 1, l) or issubstring('error:', 1, l)
        or issubstring('FAILED', 1, l) then [^^errs ^l] -> errs; endif;
    endfor;
    if ok then npr('== install OK on ' sys_>< XR_SERIAL);
    else
        npr('!! INSTALL FAILED');
        for l in errs do npr('   ' sys_>< l); endfor;
    endif;
    ok
enddefine;

;;; LAUNCH. `extras` is appended to `am start` verbatim, e.g.
;;;   '--es pin 791051 --ez devloc true'
define xr_launch(extras);
    returnunless(need_device())(false);
    shell_lines(adb('shell am force-stop ' sys_>< PKG)) -> ;
    shell_lines(adb('logcat -c')) -> ;
    shell_lines(adb('shell am start -n ' sys_>< PKG sys_>< '/.MainActivity '
                    sys_>< extras)) -> ;
    npr('== launched ' sys_>< PKG sys_>< ' ' sys_>< extras);
    true
enddefine;

;;; NB: `log` is Pop-11's logarithm, and `lvars log = ...` is a syntax error
;;; rather than a shadowing. Hence logpath.
define xr_watch(secs, pat);
    returnunless(need_device())(false);
    lvars logpath = SCRATCH sys_>< '/xrwatch.log';
    sysobey('(' sys_>< adb('logcat -s MeshmoreXR AndroidRuntime:E')
        sys_>< ' > ' sys_>< logpath sys_>< ' 2>&1 & echo $! > /tmp/xrwatch.pid); sleep '
        sys_>< secs sys_>< '; kill $(cat /tmp/xrwatch.pid) 2>/dev/null');
    lvars dev = sysopen(logpath, 0, "line");
    lvars rep = line_repeater(dev, inits(4096));
    lvars line;
    lvars hits = 0;
    lvars crash = 0;
    repeat
        rep() -> line;
        quitif(line == termin);
        if issubstring('FATAL', 1, line) or issubstring('Exception', 1, line) then
            npr('!! ' sys_>< line);
            crash + 1 -> crash;
        elseif pat = '' or issubstring(pat, 1, line) then
            npr(line);
            hits + 1 -> hits;
        endif;
    endrepeat;
    sysclose(dev);
    npr('-- ' sys_>< hits sys_>< ' match(es), ' sys_>< crash sys_>< ' crash line(s)');
    crash = 0
enddefine;

define xr_cycle(extras, secs, pat);
    if xr_install() and xr_launch(extras) then xr_watch(secs, pat)
    else false
    endif
enddefine;

npr('xr helpers loaded: xr_install, xr_launch, xr_watch, xr_cycle');

;;; Usage, once loaded with:  load '<repo>/meshmore-xr/bin/xrdeploy.p';
;;;   xr_cycle('--es pin 791051 --ez devloc true', 45, '[type]') =>
;;;   xr_install() =>                     ;;; build + install only
;;;   xr_launch('--ez typeprobe true') => ;;; force-stop, clear log, start
;;;   xr_watch(30, '[horizon]') =>        ;;; capture and filter; crashes always shown
