#ifndef RUNNER_WINDOW_FIT_H_
#define RUNNER_WINDOW_FIT_H_

// Pure geometry for placing the main window, in physical pixels. No Win32
// calls, so the rules can be checked on their own.
namespace window_fit {

// The non-client margins between the outer window and its client area.
struct Insets {
  long left = 0;
  long top = 0;
  long right = 0;
  long bottom = 0;
};

struct Box {
  long left;
  long top;
  long width;
  long height;
};

// The outer window whose client area is |client_width| x |client_height|
// capped at the work area, with that client area centred in the work area.
inline Box CenteredOuter(long work_left, long work_top, long work_width,
                         long work_height, long client_width,
                         long client_height, const Insets& insets) {
  const long width = client_width < work_width ? client_width : work_width;
  const long height = client_height < work_height ? client_height : work_height;
  return Box{work_left + (work_width - width) / 2 - insets.left,
             work_top + (work_height - height) / 2 - insets.top,
             width + insets.left + insets.right,
             height + insets.top + insets.bottom};
}

// The minimum outer size: |min_client| capped at the work area, plus the
// insets. Never larger than what the screen can show.
inline long MinTrack(long min_client, long work, long inset_sum) {
  return (min_client < work ? min_client : work) + inset_sum;
}

}  // namespace window_fit

#endif  // RUNNER_WINDOW_FIT_H_
