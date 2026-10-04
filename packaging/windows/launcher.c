#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <shellapi.h>
#include <bcrypt.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>
#include <string.h>
#include <objbase.h>
#include <iphlpapi.h>

#define CAP 32768
#define APP_NAME L"Ironwood Reach — Local Battlefield Test"
#define AUTHORITY_PORT 8775
#define STARTUP_TIMEOUT 15000
#define ID_STATUS 101
#define ID_BUILDER 102
#define ID_GENERAL 103
#define ID_CLOSE 104
#define MONITOR_TIMER 1
#define START_TIMER 2

/* Exact, previously browser-tested battlefield-006 export. */
typedef struct { const char *url; const wchar_t *filename; const char *mime; unsigned long long bytes; const char *sha; } Asset;
static const Asset ASSETS[] = {
 {"/index.html", L"index.html", "text/html; charset=utf-8", 5710, "bf538134809dca0685fa138bc2598aa1c4fdbd668250ec2587cb08bdf904b633"},
 {"/index.js", L"index.js", "text/javascript", 315759, "e3f56ee40e6f84371053db06692cfac15e2c8659547b11c6b2dfa1996dabd981"},
 {"/index.pck", L"index.pck", "application/octet-stream", 99796, "80edc2292b93f86317a22ac62e941f06c3a32ddd2daea755c939a4bb13059192"},
 {"/index.wasm", L"index.wasm", "application/wasm", 37700666, "26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6"},
 {"/index.png", L"index.png", "image/png", 21443, "3cb4495c0b98dfbe4b663cbf2b6836473572339beb66d902367893162a70be0e"},
 {"/index.icon.png", L"index.icon.png", "image/png", 4569, "ca763509b89a0494e451611f7a4db0408645127d807048478a97ca68be5bdf96"},
 {"/index.apple-touch-icon.png", L"index.apple-touch-icon.png", "image/png", 10618, "b322e5e84b35a63e4123ff4ec709cace24592b82daab8da0bc88e9ddf2ebb6a1"},
 {"/index.audio.worklet.js", L"index.audio.worklet.js", "text/javascript", 7298, "5b476a9c9ce642c0ee4256436d1bc31d9c38f868aca0f9a8e2a57c18d2dec2a3"},
 {"/index.audio.position.worklet.js", L"index.audio.position.worklet.js", "text/javascript", 2973, "be33985bc7160d6bf9646f259cd86b259cd67b02ccb297ee5c44f8ac84327bc8"}
};
static wchar_t root[CAP], runtime_dir[CAP], authority_path[CAP], browser_path[CAP], log_path[CAP], error_text[2048];
static wchar_t profile_builder[CAP], profile_general[CAP];
static HWND main_window, status_box, builder_button, general_button;
static HANDLE authority_job, authority_process, http_thread;
static DWORD authority_pid;
static SOCKET listener = INVALID_SOCKET;
static unsigned short http_port;
static volatile LONG stopping;
static BOOL started, starting;
static HINSTANCE instance;
static int verify_checks, verify_failures;

static BOOL errorf(const wchar_t *text) {
    wcsncpy(error_text, text, 2047); error_text[2047] = 0; return FALSE;
}
static BOOL winerror(const wchar_t *action) {
    DWORD code = GetLastError();
    swprintf(error_text, 2048, L"%ls (Windows error %lu).", action, (unsigned long)code); return FALSE;
}
static BOOL join_path(wchar_t *out, const wchar_t *base, const wchar_t *tail) {
    if (wcslen(base) + wcslen(tail) + 2 >= CAP) return errorf(L"The extracted folder path is too long. Move it to a shorter path.");
    return swprintf(out, CAP, L"%ls\\%ls", base, tail) >= 0;
}
static BOOL regular_file(const wchar_t *path) {
    DWORD flags = GetFileAttributesW(path);
    return flags != INVALID_FILE_ATTRIBUTES && !(flags & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT));
}
static BOOL make_runtime(void) {
    wchar_t temp[CAP], guid_text[80]; GUID guid;
    DWORD n = GetTempPathW(CAP, temp);
    if (!n || n >= CAP || FAILED(CoCreateGuid(&guid)) || !StringFromGUID2(&guid, guid_text, 80)) return winerror(L"Cannot create a private test-session folder");
    if (swprintf(runtime_dir, CAP, L"%lsIronwoodReach-%ls", temp, guid_text) < 0) return errorf(L"The temporary folder path is too long.");
    if (!CreateDirectoryW(runtime_dir, NULL)) return winerror(L"Cannot create a private test-session folder");
    return join_path(log_path, runtime_dir, L"authority.log") && join_path(profile_builder, runtime_dir, L"Builder-profile") && join_path(profile_general, runtime_dir, L"General-profile");
}
static BOOL hash_file(const wchar_t *path, char digest[65], unsigned long long *bytes) {
    HANDLE file = INVALID_HANDLE_VALUE; BCRYPT_ALG_HANDLE alg = NULL; BCRYPT_HASH_HANDLE hash = NULL;
    unsigned char buffer[65536], out[32]; DWORD read = 0; BOOL ok = FALSE; *bytes = 0;
    file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    if (file == INVALID_HANDLE_VALUE) goto done;
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0) < 0 || BCryptCreateHash(alg, &hash, NULL, 0, NULL, 0, 0) < 0) goto done;
    for (;;) {
        if (!ReadFile(file, buffer, sizeof(buffer), &read, NULL)) goto done;
        if (!read) break;
        *bytes += read; if (BCryptHashData(hash, buffer, read, 0) < 0) goto done;
    }
    if (BCryptFinishHash(hash, out, sizeof(out), 0) < 0) goto done;
    for (int i = 0; i < 32; i++) sprintf(digest + 2 * i, "%02x", out[i]); digest[64] = 0; ok = TRUE;
done:
    if (hash) BCryptDestroyHash(hash); if (alg) BCryptCloseAlgorithmProvider(alg, 0); if (file != INVALID_HANDLE_VALUE) CloseHandle(file); return ok;
}
static BOOL validate_authority(void) {
    HANDLE file = CreateFileW(authority_path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    unsigned char dos[64], pe[26]; DWORD read; LONG offset; BOOL valid = FALSE;
    if (file == INVALID_HANDLE_VALUE) return errorf(L"Missing data\\authority.exe. Extract the entire downloaded ZIP before starting the launcher.");
    if (ReadFile(file, dos, sizeof(dos), &read, NULL) && read == sizeof(dos) && dos[0] == 'M' && dos[1] == 'Z') {
        memcpy(&offset, dos + 60, 4);
        if (offset >= 64 && offset < 16 * 1024 * 1024 && SetFilePointer(file, offset, NULL, FILE_BEGIN) != INVALID_SET_FILE_POINTER && ReadFile(file, pe, sizeof(pe), &read, NULL) && read == sizeof(pe))
            valid = memcmp(pe, "PE\0\0", 4) == 0 && pe[4] == 0x64 && pe[5] == 0x86 && pe[24] == 0x0b && pe[25] == 0x02;
    }
    CloseHandle(file);
    if (!valid) return errorf(L"The bundled authority is missing or is not a valid 64-bit Windows executable. Re-extract the original ZIP.");
    return TRUE;
}
static BOOL validate_package(void) {
    wchar_t path[CAP]; char digest[65]; unsigned long long size;
    if (!join_path(authority_path, root, L"data\\authority.exe")) return FALSE;
    if (!regular_file(authority_path)) return errorf(L"Missing or invalid data\\authority.exe. Extract the entire downloaded ZIP before starting the launcher.");
    if (!validate_authority()) return FALSE;
    if (!hash_file(authority_path, digest, &size) || size != 104659456 || strcmp(digest, "91724f15024a3a545e28ccd83134403d31ce2323a38e51c95e4dfa282f732ab6"))
        return errorf(L"The bundled Godot authority does not match official 4.6.3. Re-extract the original ZIP.");
    if (!join_path(path, root, L"data\\authority.pck") || !regular_file(path) || !hash_file(path, digest, &size) || size != 99796 || strcmp(digest, ASSETS[2].sha))
        return errorf(L"Missing or changed data\\authority.pck. Extract the entire original ZIP into a new folder.");
    for (unsigned i = 0; i < sizeof(ASSETS)/sizeof(ASSETS[0]); i++) {
        wchar_t tail[160]; swprintf(tail, 160, L"data\\web\\%ls", ASSETS[i].filename);
        if (!join_path(path, root, tail) || !regular_file(path) || !hash_file(path, digest, &size) || size != ASSETS[i].bytes || strcmp(digest, ASSETS[i].sha)) {
            swprintf(error_text, 2048, L"Missing or changed battlefield file: %ls. Extract the entire original ZIP into a new folder.", ASSETS[i].filename); return FALSE;
        }
    }
    return TRUE;
}
static BOOL send_all(SOCKET client, const char *data, size_t size) {
    while (size && !InterlockedCompareExchange(&stopping, 0, 0)) {
        int n = send(client, data, size > 65536 ? 65536 : (int)size, 0);
        if (n <= 0) return FALSE; data += n; size -= (size_t)n;
    }
    return size == 0;
}
static void response(SOCKET client, int status, const char *reason, const char *mime, unsigned long long size, BOOL head, const char *body) {
    char header[768]; int n = snprintf(header, sizeof(header), "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %llu\r\nCache-Control: no-store, max-age=0\r\nPragma: no-cache\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n", status, reason, mime, size);
    if (n > 0 && n < (int)sizeof(header) && send_all(client, header, (size_t)n) && !head && body) send_all(client, body, (size_t)size);
}
static void serve_client(SOCKET client) {
    char request[4096], method[16], target[2048], version[32], header[768], buffer[65536]; int used = 0; DWORD timeout = 2000;
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, (const char*)&timeout, sizeof(timeout)); setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, (const char*)&timeout, sizeof(timeout));
    while (used < (int)sizeof(request) - 1 && !InterlockedCompareExchange(&stopping, 0, 0)) {
        int n = recv(client, request + used, (int)sizeof(request) - 1 - used, 0); if (n <= 0) return;
        used += n; request[used] = 0; if (strstr(request, "\r\n\r\n")) break;
    }
    if (!strstr(request, "\r\n\r\n") || sscanf(request, "%15s %2047s %31s", method, target, version) != 3 || (strcmp(version,"HTTP/1.1") && strcmp(version,"HTTP/1.0"))) {
        response(client, 400, "Bad Request", "text/plain", 12, FALSE, "Bad request\n"); return;
    }
    BOOL head = !strcmp(method, "HEAD");
    if (strcmp(method, "GET") && !head) { response(client, 405, "Method Not Allowed", "text/plain", 19, FALSE, "Method not allowed\n"); return; }
    char *query = strchr(target, '?'); if (query) *query = 0;
    if (!strcmp(target,"/__ironwood_health")) {
        const char *body = "{\"owner\":\"ironwood-windows-launcher\",\"build_id\":\"battlefield-006\",\"loopback_only\":true}\n";
        response(client, 200, "OK", "application/json", strlen(body), head, body); return;
    }
    if (!strcmp(target,"/")) strcpy(target,"/index.html");
    const Asset *asset = NULL;
    for (unsigned i = 0; i < sizeof(ASSETS)/sizeof(ASSETS[0]); i++) if (!strcmp(target, ASSETS[i].url)) { asset = &ASSETS[i]; break; }
    if (!asset) { response(client, 404, "Not Found", "text/plain", 10, head, "Not found\n"); return; }
    wchar_t path[CAP], tail[160]; swprintf(tail, 160, L"data\\web\\%ls", asset->filename);
    if (!join_path(path, root, tail) || !regular_file(path)) { response(client, 404, "Not Found", "text/plain", 10, head, "Not found\n"); return; }
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    LARGE_INTEGER length;
    if (file == INVALID_HANDLE_VALUE || !GetFileSizeEx(file, &length) || (unsigned long long)length.QuadPart != asset->bytes) {
        if (file != INVALID_HANDLE_VALUE) CloseHandle(file); response(client,500,"Internal Server Error","text/plain",14,head,"Missing asset\n"); return;
    }
    int hn = snprintf(header,sizeof(header),"HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %llu\r\nCache-Control: no-store, max-age=0\r\nPragma: no-cache\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n",asset->mime,asset->bytes);
    if (hn > 0 && hn < (int)sizeof(header) && send_all(client,header,(size_t)hn) && !head) {
        DWORD read; while (!InterlockedCompareExchange(&stopping,0,0) && ReadFile(file,buffer,sizeof(buffer),&read,NULL) && read) if (!send_all(client,buffer,read)) break;
    }
    CloseHandle(file);
}
static DWORD WINAPI http_main(void *unused) {
    (void)unused;
    while (!InterlockedCompareExchange(&stopping,0,0)) {
        SOCKET client = accept(listener,NULL,NULL); if (client == INVALID_SOCKET) break;
        serve_client(client); shutdown(client,SD_BOTH); closesocket(client);
    }
    return 0;
}
static BOOL start_http(void) {
    listener = WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_NO_HANDLE_INHERIT);
    if (listener == INVALID_SOCKET) return errorf(L"Cannot create the local asset server socket.");
    BOOL exclusive = TRUE; setsockopt(listener,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,(char*)&exclusive,sizeof(exclusive));
    struct sockaddr_in address; memset(&address,0,sizeof(address)); address.sin_family=AF_INET; address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if (bind(listener,(struct sockaddr*)&address,sizeof(address)) || listen(listener,16)) return errorf(L"Cannot start the loopback-only asset server.");
    int length=sizeof(address); if (getsockname(listener,(struct sockaddr*)&address,&length)) return errorf(L"Cannot identify the local asset server address.");
    http_port=ntohs(address.sin_port); http_thread=CreateThread(NULL,0,http_main,NULL,0,NULL);
    return http_thread ? TRUE : winerror(L"Cannot start the asset server thread");
}
static BOOL port_free(void) {
    SOCKET socket=WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_NO_HANDLE_INHERIT);
    if (socket == INVALID_SOCKET) return errorf(L"Cannot check the battlefield port.");
    BOOL exclusive=TRUE; setsockopt(socket,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,(char*)&exclusive,sizeof(exclusive));
    struct sockaddr_in address; memset(&address,0,sizeof(address)); address.sin_family=AF_INET; address.sin_addr.s_addr=htonl(INADDR_LOOPBACK); address.sin_port=htons(AUTHORITY_PORT);
    BOOL free=(bind(socket,(struct sockaddr*)&address,sizeof(address))==0); closesocket(socket);
    return free ? TRUE : errorf(L"Port 8775 is already in use. Close your previous Ironwood test launcher/server, then try again. This launcher will not stop or reuse an unknown service.");
}
static BOOL connect_authority(void) {
    SOCKET socket=WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_NO_HANDLE_INHERIT); if(socket==INVALID_SOCKET)return FALSE;
    u_long nonblocking=1; ioctlsocket(socket,FIONBIO,&nonblocking);
    struct sockaddr_in address; memset(&address,0,sizeof(address)); address.sin_family=AF_INET; address.sin_addr.s_addr=htonl(INADDR_LOOPBACK); address.sin_port=htons(AUTHORITY_PORT);
    int result=connect(socket,(struct sockaddr*)&address,sizeof(address)); BOOL ready=(result==0);
    if(!ready && WSAGetLastError()==WSAEWOULDBLOCK){fd_set write,error;FD_ZERO(&write);FD_ZERO(&error);FD_SET(socket,&write);FD_SET(socket,&error);struct timeval timeout={0,100000};if(select(0,NULL,&write,&error,&timeout)>0&&FD_ISSET(socket,&write)){int e=1,len=sizeof(e);if(!getsockopt(socket,SOL_SOCKET,SO_ERROR,(char*)&e,&len)&&!e)ready=TRUE;}}
    closesocket(socket); return ready;
}
static BOOL owned_authority_listening(void) {
    DWORD bytes=0;
    if(GetExtendedTcpTable(NULL,&bytes,FALSE,AF_INET,TCP_TABLE_OWNER_PID_LISTENER,0)!=ERROR_INSUFFICIENT_BUFFER || !bytes)return FALSE;
    PMIB_TCPTABLE_OWNER_PID table=(PMIB_TCPTABLE_OWNER_PID)malloc(bytes);if(!table)return FALSE;
    BOOL owned=FALSE;
    if(GetExtendedTcpTable(table,&bytes,FALSE,AF_INET,TCP_TABLE_OWNER_PID_LISTENER,0)==NO_ERROR){
        for(DWORD i=0;i<table->dwNumEntries;i++){
            MIB_TCPROW_OWNER_PID row=table->table[i];
            if(row.dwOwningPid==authority_pid && row.dwLocalAddr==htonl(INADDR_LOOPBACK) && ntohs((u_short)row.dwLocalPort)==AUTHORITY_PORT){owned=TRUE;break;}
        }
    }
    free(table);return owned;
}
static BOOL start_authority(void) {
    if(!port_free())return FALSE;
    authority_job=CreateJobObjectW(NULL,NULL);if(!authority_job)return winerror(L"Cannot create the owned battle-server job");
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;memset(&limits,0,sizeof(limits));limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if(!SetInformationJobObject(authority_job,JobObjectExtendedLimitInformation,&limits,sizeof(limits)))return winerror(L"Cannot configure server cleanup");
    SECURITY_ATTRIBUTES inheritable={sizeof(SECURITY_ATTRIBUTES),NULL,TRUE};
    HANDLE log=CreateFileW(log_path,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,&inheritable,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    HANDLE input=CreateFileW(L"NUL",GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,&inheritable,OPEN_EXISTING,0,NULL);
    if(log==INVALID_HANDLE_VALUE||input==INVALID_HANDLE_VALUE){if(log!=INVALID_HANDLE_VALUE)CloseHandle(log);if(input!=INVALID_HANDLE_VALUE)CloseHandle(input);return winerror(L"Cannot create the battle-server log");}
    wchar_t command[CAP];
    if(swprintf(command,CAP,L"\"%ls\" --headless -- --server",authority_path)<0){CloseHandle(log);CloseHandle(input);return errorf(L"The extracted folder path is too long.");}
    STARTUPINFOW startup;PROCESS_INFORMATION process;memset(&startup,0,sizeof(startup));memset(&process,0,sizeof(process));startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESTDHANDLES;startup.hStdOutput=log;startup.hStdError=log;startup.hStdInput=input;
    BOOL ok=CreateProcessW(authority_path,command,NULL,NULL,TRUE,CREATE_SUSPENDED|CREATE_NO_WINDOW,NULL,root,&startup,&process);CloseHandle(log);CloseHandle(input);
    if(!ok)return winerror(L"Cannot start the bundled battle server");
    authority_process=process.hProcess;authority_pid=process.dwProcessId;
    if(!AssignProcessToJobObject(authority_job,process.hProcess)){TerminateProcess(process.hProcess,1);CloseHandle(process.hThread);return winerror(L"Cannot attach owned-server cleanup");}
    if(ResumeThread(process.hThread)==(DWORD)-1){TerminateProcess(process.hProcess,1);CloseHandle(process.hThread);return winerror(L"Cannot resume the bundled server");}CloseHandle(process.hThread);
    DWORD at=GetTickCount();while(GetTickCount()-at<STARTUP_TIMEOUT){
        if(WaitForSingleObject(authority_process,0)!=WAIT_TIMEOUT)return errorf(L"The bundled server exited before it was ready. The log folder is shown in this launcher.");
        if(owned_authority_listening()&&connect_authority()&&WaitForSingleObject(authority_process,0)==WAIT_TIMEOUT)return TRUE;
        Sleep(50);
    }
    return errorf(L"The bundled server did not become ready within 15 seconds. The log folder is shown in this launcher.");
}
static BOOL find_browser(void) {
    const wchar_t *rel[]={L"Microsoft\\Edge\\Application\\msedge.exe",L"Google\\Chrome\\Application\\chrome.exe"};
    const wchar_t *env[]={L"ProgramFiles(x86)",L"ProgramFiles",L"LOCALAPPDATA"};wchar_t base[CAP];
    for(unsigned r=0;r<2;r++)for(unsigned e=0;e<3;e++){DWORD n=GetEnvironmentVariableW(env[e],base,CAP);if(n&&n<CAP&&join_path(browser_path,base,rel[r])&&regular_file(browser_path))return TRUE;}
    const wchar_t *keys[]={L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\msedge.exe",L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\chrome.exe"};
    for(unsigned r=0;r<2;r++)for(unsigned h=0;h<2;h++){DWORD bytes=sizeof(browser_path);if(RegGetValueW(h?HKEY_LOCAL_MACHINE:HKEY_CURRENT_USER,keys[r],NULL,RRF_RT_REG_SZ,NULL,browser_path,&bytes)==ERROR_SUCCESS&&regular_file(browser_path))return TRUE;}
    return errorf(L"Microsoft Edge or Google Chrome was not found. Install one of them, then run this launcher again. Godot is already bundled; Python is not required.");
}
static BOOL open_browser(const wchar_t *profile) {
    wchar_t command[CAP];
    if(swprintf(command,CAP,L"\"%ls\" --user-data-dir=\"%ls\" --no-first-run --no-default-browser-check --app=\"http://127.0.0.1:%u/index.html\"",browser_path,profile,(unsigned)http_port)<0)return errorf(L"The browser command is too long. Move the extracted folder to a shorter path.");
    STARTUPINFOW startup;PROCESS_INFORMATION process;memset(&startup,0,sizeof(startup));memset(&process,0,sizeof(process));startup.cb=sizeof(startup);
    if(!CreateProcessW(browser_path,command,NULL,NULL,FALSE,0,NULL,NULL,&startup,&process))return winerror(L"Cannot open the dedicated browser client");
    CloseHandle(process.hThread);CloseHandle(process.hProcess);return TRUE;
}
static void cleanup(void) {
    InterlockedExchange(&stopping,1);
    if(listener!=INVALID_SOCKET){closesocket(listener);listener=INVALID_SOCKET;}
    if(http_thread){WaitForSingleObject(http_thread,4000);CloseHandle(http_thread);http_thread=NULL;}
    if(authority_job){TerminateJobObject(authority_job,0);CloseHandle(authority_job);authority_job=NULL;}
    if(authority_process){WaitForSingleObject(authority_process,2000);CloseHandle(authority_process);authority_process=NULL;}
    started=FALSE;
}
static void show_status(const wchar_t *state) {
    wchar_t text[CAP];
    swprintf(text,CAP,L"%ls\r\n\r\n1. In the first game window choose Join Builder.\r\n2. In the second game window choose Join General.\r\n3. Click Ready in BOTH game windows to start.\r\n\r\nBuilder constructs defenses; General recruits and commands troops.\r\nGeneral: left-click selects; right-click moves; A then click attacks.\r\nQ / E abilities; mouse wheel zoom; arrow keys pan. Controls opens help.\r\n\r\nKeep this launcher open. Closing it ends this unsaved local battle.\r\nClose the two game windows afterwards.\r\n\r\nTo test again, close these windows and reopen the launcher.",state);
    SetWindowTextW(status_box,text);UpdateWindow(main_window);
}
static void report_error(void) {
    wchar_t text[CAP];swprintf(text,CAP,L"%ls\r\n\r\nSession log folder:\r\n%ls",error_text,runtime_dir);
    MessageBoxW(main_window,text,APP_NAME,MB_OK|MB_ICONERROR);
}
static LRESULT CALLBACK window_proc(HWND window,UINT message,WPARAM wparam,LPARAM lparam) {
    switch(message){
    case WM_CREATE:
        status_box=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",L"",WS_CHILD|WS_VISIBLE|ES_LEFT|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|WS_VSCROLL,16,16,650,352,window,(HMENU)(INT_PTR)ID_STATUS,instance,NULL);
        builder_button=CreateWindowW(L"BUTTON",L"Open Builder window",WS_CHILD|WS_VISIBLE|WS_DISABLED,16,382,210,34,window,(HMENU)(INT_PTR)ID_BUILDER,instance,NULL);
        general_button=CreateWindowW(L"BUTTON",L"Open General window",WS_CHILD|WS_VISIBLE|WS_DISABLED,236,382,210,34,window,(HMENU)(INT_PTR)ID_GENERAL,instance,NULL);
        CreateWindowW(L"BUTTON",L"End local test",WS_CHILD|WS_VISIBLE,456,382,210,34,window,(HMENU)(INT_PTR)ID_CLOSE,instance,NULL);
        for(HWND child=GetWindow(window,GW_CHILD);child;child=GetWindow(child,GW_HWNDNEXT))SendMessageW(child,WM_SETFONT,(WPARAM)GetStockObject(DEFAULT_GUI_FONT),TRUE);
        SetTimer(window,START_TIMER,100,NULL);return 0;
    case WM_TIMER:
        if(wparam==START_TIMER){
            KillTimer(window,START_TIMER);starting=TRUE;show_status(L"Verifying the bundled build and starting the local battle…");
            if(validate_package()&&find_browser()&&start_authority()&&start_http()&&open_browser(profile_builder)&&open_browser(profile_general)){
                started=TRUE;show_status(L"Local battle server is running. Two independent game windows are opening.");EnableWindow(builder_button,TRUE);EnableWindow(general_button,TRUE);SetTimer(window,MONITOR_TIMER,1000,NULL);
            }else{cleanup();show_status(L"The local test could not start. See the error for the exact next step.");report_error();}
            starting=FALSE;return 0;
        }
        if(wparam==MONITOR_TIMER&&started&&((authority_process&&WaitForSingleObject(authority_process,0)!=WAIT_TIMEOUT)||(http_thread&&WaitForSingleObject(http_thread,0)!=WAIT_TIMEOUT))){
            KillTimer(window,MONITOR_TIMER);cleanup();EnableWindow(builder_button,FALSE);EnableWindow(general_button,FALSE);errorf(L"The local server stopped. Close both game windows and this launcher, then start a fresh test. The previous unsaved battlefield is no longer recoverable.");show_status(error_text);report_error();
        }return 0;
    case WM_COMMAND:
        if(LOWORD(wparam)==ID_CLOSE){SendMessageW(window,WM_CLOSE,0,0);return 0;}
        if(started&&LOWORD(wparam)==ID_BUILDER){if(!open_browser(profile_builder))report_error();return 0;}
        if(started&&LOWORD(wparam)==ID_GENERAL){if(!open_browser(profile_general))report_error();return 0;}
        break;
    case WM_CLOSE:
        if(starting)return 0;
        KillTimer(window,MONITOR_TIMER);KillTimer(window,START_TIMER);cleanup();DestroyWindow(window);return 0;
    case WM_DESTROY:PostQuitMessage(0);return 0;
    }return DefWindowProcW(window,message,wparam,lparam);
}

/* Native Windows self-check: no browsers, no game-seat mutations, no authority. */
static void check(BOOL value) {verify_checks++;if(!value)verify_failures++;}
static BOOL http_test(const char *method,const char *target,int status,const char *mime,unsigned long long length,BOOL body_expected) {
    SOCKET client=WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_NO_HANDLE_INHERIT);if(client==INVALID_SOCKET)return FALSE;
    DWORD timeout=5000;setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,(char*)&timeout,sizeof(timeout));
    struct sockaddr_in address;memset(&address,0,sizeof(address));address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=htons(http_port);
    if(connect(client,(struct sockaddr*)&address,sizeof(address))){closesocket(client);return FALSE;}
    char request[4096];int n=snprintf(request,sizeof(request),"%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",method,target);
    if(n<=0||n>=(int)sizeof(request)||!send_all(client,request,(size_t)n)){closesocket(client);return FALSE;}
    char data[16384];size_t used=0;while(used<sizeof(data)-1){n=recv(client,data+used,(int)(sizeof(data)-1-used),0);if(n==0)break;if(n<0){closesocket(client);return FALSE;}used+=(size_t)n;}closesocket(client);data[used]=0;
    char *split=strstr(data,"\r\n\r\n");if(!split)return FALSE;*split=0;int actual=0;sscanf(data,"HTTP/1.1 %d",&actual);
    char content_type[160],content_length[100];snprintf(content_type,sizeof(content_type),"Content-Type: %s\r\n",mime);snprintf(content_length,sizeof(content_length),"Content-Length: %llu\r\n",length);
    if(actual!=status||!strstr(data,content_type)||!strstr(data,content_length)||!strstr(data,"Cache-Control: no-store, max-age=0\r\n"))return FALSE;
    size_t body=used-(size_t)(split+4-data);if(body!=(body_expected?(size_t)length:0))return FALSE;
    if(status==200&&body_expected&&!strcmp(target,"/index.html")){
        unsigned char digest[32];BCRYPT_ALG_HANDLE alg=NULL;BCRYPT_HASH_HANDLE hash=NULL;char hex[65];BOOL ok=FALSE;
        if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,NULL,0)>=0&&BCryptCreateHash(alg,&hash,NULL,0,NULL,0,0)>=0&&BCryptHashData(hash,(PUCHAR)(split+4),(ULONG)body,0)>=0&&BCryptFinishHash(hash,digest,sizeof(digest),0)>=0){for(int i=0;i<32;i++)sprintf(hex+2*i,"%02x",digest[i]);hex[64]=0;ok=!strcmp(hex,ASSETS[0].sha);}if(hash)BCryptDestroyHash(hash);if(alg)BCryptCloseAlgorithmProvider(alg,0);return ok;
    }
    return TRUE;
}
static BOOL http_binary_test(const Asset *asset) {
    SOCKET client=WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_NO_HANDLE_INHERIT);
    if(client==INVALID_SOCKET)return FALSE;
    DWORD timeout=5000;setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,(char*)&timeout,sizeof(timeout));
    struct sockaddr_in address;memset(&address,0,sizeof(address));address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=htons(http_port);
    BCRYPT_ALG_HANDLE alg=NULL;BCRYPT_HASH_HANDLE hash=NULL;BOOL ok=FALSE;
    if(connect(client,(struct sockaddr*)&address,sizeof(address)))goto done;
    char request[4096];int n=snprintf(request,sizeof(request),"GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",asset->url);
    if(n<=0||n>=(int)sizeof(request)||!send_all(client,request,(size_t)n))goto done;
    if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,NULL,0)<0||BCryptCreateHash(alg,&hash,NULL,0,NULL,0,0)<0)goto done;
    char header[4096],buffer[65536];size_t head_used=0;BOOL body=FALSE;unsigned long long bytes=0;
    for(;;){
        n=recv(client,buffer,sizeof(buffer),0);if(n==0)break;if(n<0)goto done;int first=0;
        if(!body){
            for(;first<n;first++){
                if(head_used>=sizeof(header)-1)goto done;header[head_used++]=buffer[first];header[head_used]=0;
                if(head_used>=4&&!memcmp(header+head_used-4,"\r\n\r\n",4)){
                    char type[160],length[100];snprintf(type,sizeof(type),"Content-Type: %s\r\n",asset->mime);snprintf(length,sizeof(length),"Content-Length: %llu\r\n",asset->bytes);
                    if(strncmp(header,"HTTP/1.1 200 OK\r\n",17)||!strstr(header,type)||!strstr(header,length)||!strstr(header,"Cache-Control: no-store, max-age=0\r\n"))goto done;
                    body=TRUE;first++;break;
                }
            }
        }
        if(body&&first<n){bytes+=(unsigned)(n-first);if(bytes>asset->bytes||BCryptHashData(hash,(PUCHAR)(buffer+first),(ULONG)(n-first),0)<0)goto done;}
    }
    if(body&&bytes==asset->bytes){unsigned char digest[32];char hex[65];if(BCryptFinishHash(hash,digest,sizeof(digest),0)>=0){for(int i=0;i<32;i++)sprintf(hex+2*i,"%02x",digest[i]);hex[64]=0;ok=!strcmp(hex,asset->sha);}}
done:
    if(hash)BCryptDestroyHash(hash);if(alg)BCryptCloseAlgorithmProvider(alg,0);closesocket(client);return ok;
}
static BOOL write_report(const wchar_t *path) {
    HANDLE file=CreateFileW(path,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);if(file==INVALID_HANDLE_VALUE)return FALSE;
    char json[1024];int n=snprintf(json,sizeof(json),"{\"mode\":\"windows-native-launcher-self-check\",\"build_id\":\"battlefield-006\",\"checks\":%d,\"failures\":%d,\"passed\":%s,\"scope\":\"official authority hash, adjacent matching PCK, nine Web hashes, x64 authority PE, real loopback HTTP requests; no Windows gameplay, browser, or authority launch claim\"}\n",verify_checks,verify_failures,verify_failures?"false":"true");DWORD written;BOOL ok=WriteFile(file,json,(DWORD)n,&written,NULL)&&written==(DWORD)n;CloseHandle(file);return ok;
}
static int verify_mode(const wchar_t *report_path) {
    check(validate_package());if(!verify_failures){check(start_http());if(!verify_failures){
        check(http_test("GET","/index.html",200,"text/html; charset=utf-8",5710,TRUE));
        check(http_test("HEAD","/index.wasm",200,"application/wasm",37700666,FALSE));
        check(http_test("HEAD","/index.js",200,"text/javascript",315759,FALSE));
        check(http_binary_test(&ASSETS[2]));
        check(http_binary_test(&ASSETS[3]));
        check(http_test("GET","/favicon.ico",404,"text/plain",10,TRUE));
        check(http_test("GET","/../data/authority.exe",404,"text/plain",10,TRUE));
        check(http_test("GET","/%2e%2e/data/authority.exe",404,"text/plain",10,TRUE));
        check(http_test("GET","/index.html?cache=fresh",200,"text/html; charset=utf-8",5710,TRUE));
        check(http_test("HEAD","/index.html",200,"text/html; charset=utf-8",5710,FALSE));
        check(http_test("PUT","/index.html",405,"text/plain",19,TRUE));
    }}cleanup();return write_report(report_path)&&!verify_failures?0:1;
}
static BOOL write_live_report(const wchar_t *path,const char *phase) {
    HANDLE file=CreateFileW(path,GENERIC_WRITE,FILE_SHARE_READ,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);if(file==INVALID_HANDLE_VALUE)return FALSE;
    char json[1200];int n=snprintf(json,sizeof(json),"{\"mode\":\"windows-launcher-owned-authority-test\",\"build_id\":\"battlefield-006\",\"phase\":\"%s\",\"checks\":%d,\"failures\":%d,\"passed\":%s,\"authority_pid\":%lu,\"authority_port\":8775,\"http_port\":%u,\"scope\":\"launcher-owned Windows authority and HTTP lifetime; no browser or Windows-PC gameplay claim\"}\n",phase,verify_checks,verify_failures,verify_failures?"false":"true",(unsigned long)authority_pid,(unsigned)http_port);DWORD written;BOOL ok=WriteFile(file,json,(DWORD)n,&written,NULL)&&written==(DWORD)n;CloseHandle(file);return ok;
}
static int verify_live_mode(const wchar_t *report_path,DWORD seconds) {
    wchar_t completed[CAP];
    if(swprintf(completed,CAP,L"%ls.completed.json",report_path)<0)return 1;
    check(validate_package());
    if(!verify_failures)check(start_authority());
    if(!verify_failures)check(start_http());
    if(!verify_failures)check(http_test("GET","/index.html",200,"text/html; charset=utf-8",5710,TRUE));
    BOOL ready=!verify_failures;
    if(!write_live_report(report_path,ready?"ready":"startup-failed")){cleanup();return 1;}
    if(ready){
        DWORD at=GetTickCount();while(GetTickCount()-at<seconds*1000){
            if(WaitForSingleObject(authority_process,0)!=WAIT_TIMEOUT||WaitForSingleObject(http_thread,0)!=WAIT_TIMEOUT){check(FALSE);break;}
            Sleep(50);
        }
    }
    cleanup();
    if(ready)check(port_free());
    return write_live_report(completed,"finished")&&!verify_failures?0:1;
}
int WINAPI WinMain(HINSTANCE application,HINSTANCE previous,LPSTR command,int show) {
    (void)previous;(void)command;instance=application;
    DWORD n=GetModuleFileNameW(NULL,root,CAP);if(!n||n>=CAP){MessageBoxW(NULL,L"Cannot locate the extracted launcher folder.",APP_NAME,MB_OK|MB_ICONERROR);return 1;}wchar_t *slash=wcsrchr(root,L'\\');if(!slash)return 1;*slash=0;
    WSADATA winsock;if(WSAStartup(MAKEWORD(2,2),&winsock))return 1;if(!make_runtime()){MessageBoxW(NULL,error_text,APP_NAME,MB_OK|MB_ICONERROR);WSACleanup();return 1;}
    int argc=0;LPWSTR *argv=CommandLineToArgvW(GetCommandLineW(),&argc);BOOL verify=FALSE,live=FALSE;DWORD seconds=30;const wchar_t *report=NULL;
    for(int i=1;i<argc;i++){
        if(!wcscmp(argv[i],L"--verify"))verify=TRUE;
        else if(!wcscmp(argv[i],L"--verify-live"))live=TRUE;
        else if(!wcscmp(argv[i],L"--verify-report")&&i+1<argc)report=argv[++i];
        else if(!wcscmp(argv[i],L"--seconds")&&i+1<argc){long value=wcstol(argv[++i],NULL,10);if(value<1||value>120){LocalFree(argv);WSACleanup();return 1;}seconds=(DWORD)value;}
    }
    if(verify||live){wchar_t fallback[CAP];if(!report){join_path(fallback,runtime_dir,L"launcher-verification.json");report=fallback;}int result=live?verify_live_mode(report,seconds):verify_mode(report);LocalFree(argv);WSACleanup();return result;}LocalFree(argv);
    WNDCLASSW cls;memset(&cls,0,sizeof(cls));cls.lpfnWndProc=window_proc;cls.hInstance=application;cls.lpszClassName=L"IronwoodReachLocalLauncher006";cls.hCursor=LoadCursor(NULL,IDC_ARROW);cls.hIcon=LoadIcon(NULL,IDI_APPLICATION);cls.hbrBackground=(HBRUSH)(COLOR_BTNFACE+1);
    if(!RegisterClassW(&cls)){WSACleanup();return 1;}main_window=CreateWindowW(cls.lpszClassName,APP_NAME,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX,CW_USEDEFAULT,CW_USEDEFAULT,700,470,NULL,NULL,application,NULL);
    if(!main_window){cleanup();WSACleanup();return 1;}ShowWindow(main_window,show);UpdateWindow(main_window);
    MSG message;int result;while((result=GetMessageW(&message,NULL,0,0))>0){TranslateMessage(&message);DispatchMessageW(&message);}cleanup();WSACleanup();return result==-1?1:(int)message.wParam;
}
