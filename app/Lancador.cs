// Claude Remote Manager - lançador (.exe).
// O programa é feito em PowerShell (app\Janela.ps1). Este .exe roda esse script dentro do próprio
// processo, para o programa aparecer como "Claude Remote Manager" no Gerenciador de Tarefas e na barra.
// O .exe já vem pronto no zip do site (compilado na publicação, ferramentas/Gerar-Exe.sh).
// O PowerShell do Windows é carregado em tempo de execução (reflexão), então não precisa dele para compilar.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

public static class CrmLancador
{
    [DllImport("kernel32.dll")] static extern bool AllocConsole();
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr janela, int modo);

    static bool EhAdmin()
    {
        try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
        catch { return false; }
    }

    static MethodInfo Metodo(Type t, string nome, Type[] tipos)
    {
        foreach (MethodInfo m in t.GetMethods())
        {
            if (m.Name != nome || m.IsGenericMethodDefinition) continue;
            ParameterInfo[] ps = m.GetParameters();
            if (ps.Length != tipos.Length) continue;
            bool ok = true;
            for (int i = 0; i < ps.Length; i++) if (ps[i].ParameterType != tipos[i]) { ok = false; break; }
            if (ok) return m;
        }
        throw new MissingMethodException(t.FullName, nome);
    }

    static void RodarScript(string script)
    {
        Assembly sma = Assembly.Load("System.Management.Automation, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35");
        Type tIss = sma.GetType("System.Management.Automation.Runspaces.InitialSessionState", true);
        Type tPol = sma.GetType("Microsoft.PowerShell.ExecutionPolicy", true);
        Type tFab = sma.GetType("System.Management.Automation.Runspaces.RunspaceFactory", true);
        Type tRs = sma.GetType("System.Management.Automation.Runspaces.Runspace", true);
        Type tOpc = sma.GetType("System.Management.Automation.Runspaces.PSThreadOptions", true);
        Type tPs = sma.GetType("System.Management.Automation.PowerShell", true);

        object iss = Metodo(tIss, "CreateDefault", Type.EmptyTypes).Invoke(null, null);
        tIss.GetProperty("ExecutionPolicy").SetValue(iss, Enum.Parse(tPol, "Bypass"), null);
        object rs = Metodo(tFab, "CreateRunspace", new Type[] { tIss }).Invoke(null, new object[] { iss });
        try
        {
            tRs.GetProperty("ApartmentState").SetValue(rs, ApartmentState.STA, null);
            tRs.GetProperty("ThreadOptions").SetValue(rs, Enum.Parse(tOpc, "UseCurrentThread"), null);
            Metodo(tRs, "Open", Type.EmptyTypes).Invoke(rs, null);
            object ps = Metodo(tPs, "Create", Type.EmptyTypes).Invoke(null, null);
            try
            {
                tPs.GetProperty("Runspace").SetValue(ps, rs, null);
                Metodo(tPs, "AddCommand", new Type[] { typeof(string) }).Invoke(ps, new object[] { script });
                Metodo(tPs, "Invoke", Type.EmptyTypes).Invoke(ps, null);
            }
            finally { ((IDisposable)ps).Dispose(); }
        }
        finally { ((IDisposable)rs).Dispose(); }
    }

    [STAThread]
    public static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        string exe = Application.ExecutablePath;
        string raiz = Path.GetDirectoryName(exe);
        // Sobra de uma atualização (o .exe antigo é renomeado porque estava aberto).
        try { string velho = exe + ".old"; if (File.Exists(velho)) File.Delete(velho); } catch { }

        // O programa precisa de administrador (tarefas agendadas): pede uma vez e reabre.
        if (!EhAdmin())
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe);
                psi.UseShellExecute = true; psi.Verb = "runas"; psi.WorkingDirectory = raiz;
                Process.Start(psi);
            }
            catch { }   // recusou: não abre sem administrador
            return 0;
        }

        string script = Path.Combine(Path.Combine(raiz, "app"), "Janela.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Não achei " + script + ".\r\n\r\nO .exe precisa ficar junto da pasta app (extraia o zip inteiro).", "Claude Remote Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        // Console escondido: os comandos que o programa roda (claude.exe, taskkill...) usam ele e não abrem janelas.
        AllocConsole();
        IntPtr console = GetConsoleWindow();
        if (console != IntPtr.Zero) ShowWindow(console, 0);
        Environment.SetEnvironmentVariable("CRM_EXE", exe);
        try
        {
            RodarScript(script);
            return 0;
        }
        catch (Exception ex)
        {
            Exception real = ex;
            while (real is TargetInvocationException && real.InnerException != null) real = real.InnerException;
            // Marca a falha: na próxima vez o programa abre pelo PowerShell.
            try
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude-remote-manager");
                Directory.CreateDirectory(dir);
                File.WriteAllText(Path.Combine(dir, "exe-falhou.txt"), DateTime.Now.ToString("s") + "\r\n" + real.ToString());
            }
            catch { }
            MessageBox.Show("O programa parou com um erro:\r\n\r\n" + real.Message, "Claude Remote Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
