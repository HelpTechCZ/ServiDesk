using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.EventLog;
using RemoteAgent.Service;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "RemoteAgentService";
});

builder.Logging.AddEventLog(new EventLogSettings
{
    SourceName = "ServiDesk RemoteAgent",
    LogName = "Application"
});

builder.Services.AddHostedService<AgentService>();

var host = builder.Build();
host.Run();
