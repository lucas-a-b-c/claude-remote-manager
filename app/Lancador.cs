// Claude Remote Manager - lançador (.exe).
// O programa é feito em PowerShell (app\Janela.ps1). Este .exe só roda esse script dentro do próprio
// processo, para o programa aparecer como "Claude Remote Manager" no Gerenciador de Tarefas e na barra.
// Ele é compilado no próprio PC pelo app\Executavel.ps1 (usa o csc.exe que vem com o Windows).
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

public static class CrmLancador
{
    [DllImport("kernel32.dll")] static extern bool AllocConsole();
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr janela, int modo);

    [STAThread]
    public static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        string raiz = Path.GetDirectoryName(Application.ExecutablePath);
        string script = Path.Combine(Path.Combine(raiz, "app"), "Janela.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Não achei " + script + ".", "Claude Remote Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        // Console escondido: os comandos que o programa roda (claude.exe, taskkill...) usam ele e não abrem janelas.
        AllocConsole();
        IntPtr console = GetConsoleWindow();
        if (console != IntPtr.Zero) ShowWindow(console, 0);
        Environment.SetEnvironmentVariable("CRM_EXE", Application.ExecutablePath);
        try
        {
            InitialSessionState iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddCommand(script);
                    ps.Invoke();
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("O programa parou com um erro:\r\n\r\n" + ex.Message, "Claude Remote Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
