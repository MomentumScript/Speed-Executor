using System;
using System.Diagnostics;
using System.Windows;

namespace SpeedExecutor
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            AppDomain.CurrentDomain.UnhandledException += (s, args) =>
            {
                try { System.IO.File.WriteAllText("crash.log", args.ExceptionObject.ToString()); } catch { }
            };
            DispatcherUnhandledException += (s, args) =>
            {
                try { System.IO.File.WriteAllText("crash.log", args.Exception.ToString()); } catch { }
            };
            base.OnStartup(e);

            

            

            uint pid = Executor.FindPid("RobloxPlayerBeta.exe");

            if (pid != 0)
            {
                Executor.Startup(pid);
            }
        }

        protected override void OnExit(ExitEventArgs e)
        {
            AiServer.Shutdown();
            Executor.Shutdown();
            base.OnExit(e);
        }
    }
}
