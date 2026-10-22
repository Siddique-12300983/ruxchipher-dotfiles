/* conky-clickable: give an undecorated conky window its mouse input back.
 *
 * Conky clears the X input shape of undecorated windows so clicks pass through to
 * the desktop, which also stops lua_mouse_hook from ever firing. This resets the
 * input shape to the whole window for every window whose title matches.
 *
 *   conky-clickable ruxchipher-hud ruxchipher-wx
 *
 * Build: cc -O2 -o conky-clickable conky-clickable.c -lX11 -lXext
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/shape.h>
#include <stdio.h>
#include <string.h>

static int fixed;

static void walk(Display *d, Window w, int argc, char **argv) {
    char *name = NULL;
    if (XFetchName(d, w, &name) && name) {
        for (int i = 1; i < argc; i++) {
            if (strcmp(name, argv[i]) == 0) {
                XShapeCombineMask(d, w, ShapeInput, 0, 0, None, ShapeSet);
                printf("clickable: %s (0x%lx)\n", name, w);
                fixed++;
            }
        }
        XFree(name);
    }
    Window root, parent, *kids = NULL;
    unsigned int n = 0;
    if (XQueryTree(d, w, &root, &parent, &kids, &n)) {
        for (unsigned int i = 0; i < n; i++) walk(d, kids[i], argc, argv);
        if (kids) XFree(kids);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s WINDOW_TITLE...\n", argv[0]);
        return 2;
    }
    Display *d = XOpenDisplay(NULL);
    if (!d) {
        fprintf(stderr, "cannot open X display\n");
        return 1;
    }
    walk(d, DefaultRootWindow(d), argc, argv);
    XSync(d, False);
    XCloseDisplay(d);
    return fixed ? 0 : 1;
}
