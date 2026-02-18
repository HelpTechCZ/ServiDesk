using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using RemoteAgent.Service;

namespace RemoteAgent.GUI;

public partial class App : System.Windows.Application
{
    private IHost? _serviceHost;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Oznacit ze service bezi embedded v GUI – neauto-connectovat
        Environment.SetEnvironmentVariable("SERVIDESK_EMBEDDED", "1");

        // Hostovat AgentService in-process (na pozadí)
        _serviceHost = Host.CreateDefaultBuilder()
            .ConfigureLogging(logging =>
            {
                logging.ClearProviders();
                logging.AddDebug();
                logging.SetMinimumLevel(LogLevel.Information);
            })
            .ConfigureServices(services =>
            {
                services.AddHostedService<AgentService>();
            })
            .Build();

        _ = Task.Run(async () =>
        {
            try
            {
                await _serviceHost.RunAsync();
            }
            catch (OperationCanceledException) { }
        });

        // Dát chvilku service aby nastartoval pipe server
        await Task.Delay(500);
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_serviceHost != null)
        {
            await _serviceHost.StopAsync(TimeSpan.FromSeconds(3));
            _serviceHost.Dispose();
        }
        base.OnExit(e);
    }
}
