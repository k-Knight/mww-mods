#ifndef UNICODE
#define UNICODE
#endif

#include <windows.h>
#include <stdint.h>
#include <string>
#include <vector>
#include <sstream>

typedef void (*initialize_gamepad_fn)();
typedef void (*shutdown_gamepad_fn)();
typedef bool (*get_button_state_fn)(const char*);
typedef float (*get_axis_fn)();

static initialize_gamepad_fn initialize_gamepad = nullptr;
static shutdown_gamepad_fn shutdown_gamepad = nullptr;
static get_button_state_fn get_button_state = nullptr;
static get_axis_fn get_left_axis_x = nullptr;
static get_axis_fn get_left_axis_y = nullptr;
static get_axis_fn get_right_axis_x = nullptr;
static get_axis_fn get_right_axis_y = nullptr;

static HMODULE h_gamepad_dll = NULL;

static const std::vector<std::string> button_names = {
    "d up", "d down", "d left", "d right",
    "start", "back", "l3", "r3",
    "l1", "r1", "l2", "r2",
    "a", "b", "x", "y"
};

static const UINT_PTR refresh_timer_id = 1;

static std::wstring get_win32_error_string(DWORD error_code) {
    if (error_code == 0)
        return L"no error";

    LPWSTR message_buffer = nullptr;
    size_t size = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, 
        error_code, 
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), 
        (LPWSTR)&message_buffer, 
        0, 
        NULL
    );
    
    std::wstring message(message_buffer, size);
    LocalFree(message_buffer);
    return message;
}

static bool load_gamepad_dll() {
    h_gamepad_dll = LoadLibrary(L"sdl_gamepad_listener.dll"); 
    if (!h_gamepad_dll) {
        DWORD err = GetLastError();
        std::wstringstream ss;
        ss << L"failed to load 'sdl_gamepad_listener.dll'\n"
           << L"error: " << err << L"\n"
           << L"details: " << get_win32_error_string(err);
        
        MessageBox(NULL, ss.str().c_str(), L"dll error", MB_ICONERROR);
        return false;
    }

    #define M_WideStr_Helper(x) L##x
    #define M_WideStr(x) M_WideStr_Helper(x)

    #define RESOLVE_PROC(Type, FuncName, ExportName) \
        FuncName = (Type)GetProcAddress(h_gamepad_dll, ExportName); \
        if (!FuncName) { \
            DWORD err = GetLastError(); \
            std::wstringstream ss; \
            ss << L"missing export: '" << M_WideStr(ExportName) << L"'\n" \
               << L"error: " << err << L"\n" \
               << L"details: " << get_win32_error_string(err); \
            MessageBox(NULL, ss.str().c_str(), L"link error", MB_ICONERROR); \
            FreeLibrary(h_gamepad_dll); \
            h_gamepad_dll = NULL; \
            return false; \
        }

    RESOLVE_PROC(initialize_gamepad_fn, initialize_gamepad, "initialize_gamepad");
    RESOLVE_PROC(shutdown_gamepad_fn, shutdown_gamepad, "shutdown_gamepad");
    RESOLVE_PROC(get_button_state_fn, get_button_state, "get_button_state");
    RESOLVE_PROC(get_axis_fn, get_left_axis_x, "get_left_axis_x");
    RESOLVE_PROC(get_axis_fn, get_left_axis_y, "get_left_axis_y");
    RESOLVE_PROC(get_axis_fn, get_right_axis_x, "get_right_axis_x");
    RESOLVE_PROC(get_axis_fn, get_right_axis_y, "get_right_axis_y");

    #undef RESOLVE_PROC
    #undef M_WideStr
    #undef M_WideStr_Helper

    return true;
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT u_msg, WPARAM wp, LPARAM lp) {
    switch (u_msg) {
        case WM_CREATE: {
            if (initialize_gamepad)
                initialize_gamepad();

            SetTimer(hwnd, refresh_timer_id, 16, NULL);
            return 0;
        }
        case WM_TIMER: {
            if (wp == refresh_timer_id)
                InvalidateRect(hwnd, NULL, TRUE);

            return 0;
        }
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);

            SetBkMode(hdc, TRANSPARENT);
            SetTextColor(hdc, RGB(0, 0, 0));

            int y_offset = 20;
            std::wstring output_text;

            if (get_left_axis_x && get_left_axis_y && get_right_axis_x && get_right_axis_y) {
                output_text = L"left axis: x=" + std::to_wstring(get_left_axis_x()) + 
                             L" y=" + std::to_wstring(get_left_axis_y());
                TextOut(hdc, 20, y_offset, output_text.c_str(), (int)output_text.length());
                y_offset += 25;

                output_text = L"right axis: x=" + std::to_wstring(get_right_axis_x()) + 
                             L" y=" + std::to_wstring(get_right_axis_y());
                TextOut(hdc, 20, y_offset, output_text.c_str(), (int)output_text.length());
                y_offset += 40;
            }

            output_text = L"--- buttons ---";
            TextOut(hdc, 20, y_offset, output_text.c_str(), (int)output_text.length());
            y_offset += 25;

            if (get_button_state) {
                for (const auto& name : button_names) {
                    bool pressed = get_button_state(name.c_str());
                    
                    std::wstring w_name(name.begin(), name.end());
                    std::wstring state_str = pressed ? L"true" : L"false";
                    output_text = w_name + L": " + state_str;

                    COLORREF old_color = SetTextColor(hdc, pressed ? RGB(0, 192, 0) : RGB(192, 96, 96));
                    TextOut(hdc, 20, y_offset, output_text.c_str(), (int)output_text.length());
                    SetTextColor(hdc, old_color);

                    y_offset += 20;
                }
            }

            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_DESTROY: {
            KillTimer(hwnd, refresh_timer_id);
            if (shutdown_gamepad)
                shutdown_gamepad();

            PostQuitMessage(0);
            return 0;
        }
    }
    return DefWindowProc(hwnd, u_msg, wp, lp);
}

int WINAPI WinMain(HINSTANCE h_inst, HINSTANCE, LPSTR, int n_cmd_show) {
    if (!load_gamepad_dll())
        return 1;

    const wchar_t class_name[] = L"gamepad_viewer_class";

    WNDCLASS wc = {};
    wc.lpfnWndProc   = WindowProc;
    wc.hInstance     = h_inst;
    wc.lpszClassName = class_name;
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);

    RegisterClass(&wc);

    HWND hwnd = CreateWindowEx(
        0, class_name, L"gamepad viewer",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 350, 500,
        NULL, NULL, h_inst, NULL
    );

    if (!hwnd) 
        return 0;

    ShowWindow(hwnd, n_cmd_show);

    MSG msg = {};
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    FreeLibrary(h_gamepad_dll);
    return 0;
}
