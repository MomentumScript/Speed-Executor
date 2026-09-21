using System;
using System.Runtime.InteropServices;
using System.Text;



static class Native {
    public const uint PROCESS_ALL_ACCESS = 0x001F0FFF;
    public const uint PROCESS_DUP_HANDLE = 0x0040;
    public const uint PROCESS_QUERY_INFORMATION = 0x0400;
    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    public const uint PROCESS_VM_READ = 0x0010;
    public const uint PROCESS_VM_WRITE = 0x0020;
    public const uint PROCESS_VM_OPERATION = 0x0008;
    

    

    public const uint PROCESS_MINIMAL = PROCESS_VM_READ | PROCESS_VM_WRITE |
        PROCESS_VM_OPERATION | PROCESS_QUERY_LIMITED_INFORMATION;
    public const uint MEM_COMMIT = 0x1000, MEM_RESERVE = 0x2000, MEM_RELEASE = 0x8000;
    public const uint PAGE_READWRITE = 0x04;
    public const uint TH32CS_SNAPPROCESS = 0x2, TH32CS_SNAPMODULE = 0x8, TH32CS_SNAPMODULE32 = 0x10;
    public const uint STILL_ACTIVE = 259;
    public const int SW_SHOW = 5;
    public const uint WM_SETREDRAW = 0x000B;
    public const uint WM_NCLBUTTONDOWN = 0xA1;
    public const uint EM_GETSCROLLPOS = 0x400 + 221;
    public const uint EM_SETSCROLLPOS = 0x400 + 222;
    public const uint DUPLICATE_CLOSE_SOURCE = 0x1;

    public const int GWL_STYLE = -16;
    public const long WS_THICKFRAME = 0x00040000L;
    public const long WS_MAXIMIZEBOX = 0x00010000L;
    public const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOZORDER = 0x0004, SWP_NOACTIVATE = 0x0010;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
        public int Width => Right - Left;
        public int Height => Bottom - Top;
    }

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int nIndex);
    [DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int nIndex, IntPtr dwNewLong);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int n, out int read);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int n, out int written);
    [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, int size, uint type, uint prot);
    [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr h, IntPtr addr, int size, uint type);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] public static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool Process32FirstW(IntPtr s, ref PROCESSENTRY32W pe);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool Process32NextW(IntPtr s, ref PROCESSENTRY32W pe);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool Module32FirstW(IntPtr s, ref MODULEENTRY32W me);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool Module32NextW(IntPtr s, ref MODULEENTRY32W me);
    [DllImport("kernel32.dll")] public static extern uint GetTickCount();

    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern int GetWindowTextA(IntPtr h, StringBuilder b, int n);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool c);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] ins, int size);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, ref POINT l);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern int MessageBoxA(IntPtr h, string t, string c, uint type);
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyA(uint code, uint map);

    [DllImport("ntdll.dll")] public static extern int NtQuerySystemInformation(uint cls, IntPtr buf, uint len, out uint ret);
    [DllImport("ntdll.dll")] public static extern int NtDuplicateObject(IntPtr srcProc, IntPtr srcHandle, IntPtr dstProc, out IntPtr dst, uint access, uint attr, uint opts);
    [DllImport("ntdll.dll")] public static extern int NtQueryObject(IntPtr h, uint cls, IntPtr buf, uint len, out uint ret);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PROCESSENTRY32W {
        public uint dwSize, cntUsage, th32ProcessID, th32DefaultHeapID, th32ModuleID, cntThreads, th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MODULEENTRY32W {
        public uint dwSize, th32ModuleID, th32ProcessID, GlblcntUsage, ProccntUsage;
        public IntPtr modBaseAddr;
        public uint modBaseSize;
        public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExePath;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx, dy, mouseData, dwFlags, time; public IntPtr extra; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public short wVk, wScan; public int dwFlags, time; public IntPtr extra; }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public int type; public INPUTUNION u; }

    [StructLayout(LayoutKind.Sequential)]
    public struct UNICODE_STRING { public ushort Length, MaximumLength; public IntPtr Buffer; }
}
