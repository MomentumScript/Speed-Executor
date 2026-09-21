



static class Off {
    public const int BridgePort = 9475;

    public static string ClientVersion = "version-c5aecda2245e4fae";

    public static ulong FDM_Pointer = 0x8dc2258;
    public static ulong FDM_RealDataModel = 0x1f8;

    public static ulong Instance_Name = 0x8;
    public static ulong Instance_NameContainer = 0x70;
    public static ulong Instance_ClassDesc = 0x18;
    public static ulong Instance_ClassName = 0x8;
    public static ulong Instance_Parent = 0x68;
    public static ulong Instance_ChildrenStart = 0x78;
    public static ulong Instance_ChildrenEnd = 0x8;

    public static ulong Module_BC = 0x138;
    public static ulong Local_BC = 0x190;
    public static ulong BC_Ptr = 0x18; 

    public static ulong BC_Size = 0x28;
    public static ulong Module_State = 0x170;

    public static ulong Misc_Value = 0xb8;

    

    public static ulong FFlag_EnableLoadModule = 0x8496288;

    public static ulong TaskSchedulerTargetFps = 0x81a8d78;
    public static ulong FFlagDebugSkyGray = 0x8489218;

    

    

    public static string OffsetsText() {
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        System.Action<string, ulong> add = (name, v) => sb.Append(name).Append('=').Append("0x").Append(v.ToString("x")).Append('\n');
        add("FDM_Pointer", FDM_Pointer);
        add("FDM_RealDataModel", FDM_RealDataModel);
        add("Instance_Name", Instance_Name);
        add("Instance_NameContainer", Instance_NameContainer);
        add("Instance_ClassDesc", Instance_ClassDesc);
        add("Instance_ClassName", Instance_ClassName);
        add("Instance_Parent", Instance_Parent);
        add("Instance_ChildrenStart", Instance_ChildrenStart);
        add("Instance_ChildrenEnd", Instance_ChildrenEnd);
        add("Module_BC", Module_BC);
        add("Local_BC", Local_BC);
        add("BC_Ptr", BC_Ptr);
        add("BC_Size", BC_Size);
        add("Module_State", Module_State);
        add("Misc_Value", Misc_Value);
        add("FFlag_EnableLoadModule", FFlag_EnableLoadModule);
        return sb.ToString();
    }
}
