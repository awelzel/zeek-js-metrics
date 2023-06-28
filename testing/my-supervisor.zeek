@load base/frameworks/cluster
@load base/frameworks/reporter

redef LogAscii::use_json = T;
redef Broker::disable_ssl = F;


redef Reporter::info_to_stderr = T;
redef Reporter::warnings_to_stderr = T;
redef Reporter::errors_to_stderr = T;

event zeek_init()
	{
	if ( ! Supervisor::is_supervisor() )
		return;

	Broker::listen("127.0.0.1", 9999/tcp);

	local cluster: table[string] of Supervisor::ClusterEndpoint;
	cluster["manager"] = [$role=Supervisor::MANAGER, $host=127.0.0.1, $p=10000/tcp];
	cluster["proxy"] = [$role=Supervisor::PROXY, $host=127.0.0.1, $p=10001/tcp];

	local loggers = 1;
	local i = 0;
	while ( i < loggers )
		{
		++i;
		local lp = count_to_port(10010 + i, tcp);
		local logger_name = fmt("logger-%03d", i);
		cluster[logger_name] = [$role=Supervisor::LOGGER, $host=127.0.0.1, $p=lp];
		}

	local workers = 16;
	local worker_port_offset = 10100;
	i = 0;
	while ( i < workers )
		{
		++i;
		local name = fmt("worker-%03d", i);
		# local p = count_to_port(worker_port_offset + i, tcp);
		cluster[name] = [$role=Supervisor::WORKER, $host=127.0.0.1, $p=0/tcp, $interface="dummy0"];
		}

	i = 0;
	for ( n, ep in cluster )
		{
		++i;
		local sn = Supervisor::NodeConfig($name=n);
		sn$cluster = cluster;
		sn$directory = n;
		sn$env = table(["ZEEK_DEFAULT_CONNECT_RETRY"] = "1");

    print "XXXXX", n;
    if ( n == "manager") {
		  sn$env = table(["ZEEK_DEFAULT_CONNECT_RETRY"] = "1");
      sn$env["MALLOC_CONF"] = "stats_print:true;prof:true,prof_prefix:jeprof.out,prof_final:true,lg_prof_interval:28";
      sn$env["LD_PRELOAD"] = "/usr/local/lib/libjemalloc.so";

      print "XXXXX MANAGER XXXX", sn$env;
    }

		if ( ep?$interface )
			sn$interface = ep$interface;

		local res = Supervisor::create(sn);
		if ( res != "" )
			Reporter::error(fmt("supervisor failed to create node '%s': %s", sn, res));
		}
	}
