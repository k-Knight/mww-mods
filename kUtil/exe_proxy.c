#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <shlwapi.h>
#include <stdarg.h>

#pragma comment(lib, "Shlwapi.lib")
#pragma comment(lib, "User32.lib")

#define PATH_LEN 4096

char log_filepath[PATH_LEN];

void log_to_file(const char *format, ...) {
    char buffer[PATH_LEN * 2];
    va_list args;

    va_start(args, format);
    vsprintf(buffer, format, args);
    va_end(args);

    FILE *fp = fopen(log_filepath, "a");
    if (fp != NULL) {
        setvbuf(fp, NULL, _IONBF, 0); 
        fprintf(fp, "%s\n", buffer);
        fclose(fp);
    }
}

void escape_quotes_to_buffer(const char* src, char* dest) {
    while (*src) {
        if (*src == '"') {
            *dest++ = '"';
            *dest++ = '"';
        } else
            *dest++ = *src;

        src++;
    }

    *dest = '\0';
}

int PrepareConsole(const char* target_cmd) {
    char alacrittyPath[MAX_PATH] = "alacritty.exe";
    
    if (PathFindOnPathA(alacrittyPath, NULL)) {
        char escaped_cmd[PATH_LEN * 2];
        char alacritty_cmd[PATH_LEN * 2];

        escape_quotes_to_buffer(target_cmd, escaped_cmd);
        _snprintf(alacritty_cmd, sizeof(alacritty_cmd), "alacritty.exe --hold --command \"C:\\Windows\\System32\\cmd.exe /c \"\"%s\"\"\"", escaped_cmd);

        STARTUPINFOA si = { sizeof(si) };
        PROCESS_INFORMATION pi = { 0 };

        log_to_file("[exe_proxy] trying to spawn alacritty ::\n\t%s\n", alacritty_cmd);
        if (CreateProcessA(NULL, alacritty_cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
            WaitForSingleObject(pi.hProcess, INFINITE);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return 1;
        }

        log_to_file("[exe_proxy] could not launch :: error %lu\n", GetLastError());
    }

    AllocConsole();
    return 0;
}

void change_path_postfix(const char *src, char *dest, const char *extension, const char *postfix) {
    strcpy(dest, src);

    char* dot = strrchr(dest, '.');
    if (dot && _stricmp(dot, extension) == 0)
        strcpy(dot, postfix);
    else
        strcat(dest, postfix);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nShowCmd) {
    char exePath[PATH_LEN * 2];
    char targetName[PATH_LEN];

    GetModuleFileNameA(NULL, exePath, sizeof(exePath));

    change_path_postfix(exePath, targetName, ".exe", "_orig.exe");
    change_path_postfix(exePath, log_filepath, ".exe", ".log");

    char* cmdLine = GetCommandLineA();
    char* args = NULL;

    if (cmdLine[0] == '"') {
        args = strchr(cmdLine + 1, '"');

        if (args)
            args = strchr(args, ' ');
    } else
        args = strchr(cmdLine, ' ');

    if (!args)
        args = "";

    _snprintf(exePath, sizeof(exePath), "\"%s\" %s", targetName, args);
    log_to_file("[exe_proxy] launching executable with args\n\t%s\n", exePath);

    if (PrepareConsole(exePath)) {
        return 0;
    }

    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi = { 0 };

    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    if (CreateProcessA(
        NULL,
        exePath,
        NULL,
        NULL,
        TRUE,
        0,
        NULL,
        NULL,
        &si,
        &pi
    )) {
        WaitForSingleObject(pi.hProcess, INFINITE);
        
        DWORD exitCode = 0;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);

        system("pause"); 
        return (int)exitCode;
    }

    log_to_file("[exe_proxy] could not launch %s (error %lu)\n", targetName, GetLastError());

    system("pause"); 
    return 1;
}
