@if ( ! Supervisor::is_supervisor() )

global update_interval: interval = 1sec;

global nfamilies = 4;
global ncounters_per_family = 400;

type Counters: record {
  f: Telemetry::CounterFamily;
  counters: vector of Telemetry::Counter;
};


global my_families: vector of Counters;
global counters: vector of Telemetry::Counter;

event update_telemetry() {
        schedule update_interval { update_telemetry() };

        for ( _, f in my_families ) {
                for ( _, c in f$counters ) {
                        Telemetry::counter_inc(c, rand(10));
                }
        }
}

event zeek_init() {
        local i = 0;
        while ( i < nfamilies ) {
                local f = Counters(
                        $f=Telemetry::register_counter_family([
                                $prefix="zeek",
                                $name=fmt("test_%d", i),
                                $unit="stuff",
                                $help_text=fmt("stuff %d", i),
                                $labels=vector("label1", "label2"),
                        ]),
                        $counters=vector(),
                );
                my_families[i] = f;
                local j = 0;
                while ( j < ncounters_per_family ) {
                        local labels = vector(cat(i), cat(j));
                        f$counters += Telemetry::counter_with(f$f, labels);
                        ++j;
                }
                ++i;
        }

        schedule update_interval { update_telemetry() };

}
@endif
