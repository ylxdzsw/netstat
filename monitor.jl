using Fire
using Dates
using JSON2
using Random
using Restful
using OhMyJulia
using Statistics
using JsonBuilder

function get_info()
    data = map(JSON2.read, readlines("result")[max(end-150000, 1):end])
    conn = floor(Int, 100mean(endswith(x.status, "succeed") for x in data[max(end-300, 1):end] if startswith(x.status, "ping")))
    speed = let x = filter(x->startswith(x.status, "speedtest"), data)[end]
        endswith(x.status, "succeed") ? round.((x.download, x.upload), sigdigits=4) : ("NaN", "NaN")
    end
    dns = let x = filter(x->x.status == "dns succeed", data[max(end-300, 1):end])
        length(x) == 0 ? "NaN" : round(mean(x->1000x.elapsed, x), digits=1)
    end
    hosts = let x = filter(x->startswith(x.status, "arp-scan"), data)[end]
        endswith(x.status, "succeed") ? (x.hosts, x.duplicates) : ("NaN", "NaN")
    end

    plot1 = let pings = filter(x->x.status == "ping succeed", data)
        series = []
        for (site, list) in groupby(x->x.website, push!, ()->[], pings)
            points = [(time, 333mean(ps)) for (time, ps) in groupby(x->x.timestamp[1:11], (x, y) -> push!(x, y.elapsed), ()->f64[], list)]
            push!(series, @json """{
                name: $site,
                type: 'line',
                data: $(sort(points)),
                smooth: true
            }""")
        end

        @json """{
            backgroundColor: 'transparent',
            title: { text: 'Ping' },
            xAxis: { type: 'category' },
            yAxis: { type: 'value', name: 'Latency (ms)', max: 1000 },
            legend: { width: 400 },
            tooltip: { trigger: 'axis' },
            dataZoom: [{
                type: 'slider',
                start: 90,
                height: 20,
                bottom: 12
            }],
            series: [$(join(series, ','))!]
        }"""
    end

    plot2 = let speeds = filter(x->x.status == "speedtest succeed", data)
        @json """{
            backgroundColor: 'transparent',
            title: { text: 'Speed' },
            xAxis: { type: 'category' },
            yAxis: { type: 'value', name: 'Speed (Mbps)' },
            legend: {},
            tooltip: { trigger: 'axis' },
            dataZoom: [{
                type: 'slider',
                start: 60,
                height: 20,
                bottom: 12
            }],
            series: [{
                name: 'download',
                type: 'line',
                data: $(sort(map(x->(x.timestamp[1:11], x.download), speeds))),
                smooth: true
            }, {
                name: 'upload',
                type: 'line',
                data: $(sort(map(x->(x.timestamp[1:11], x.upload), speeds))),
                smooth: true
            }]
        }"""
    end

    plot3 = let hosts = filter(x->x.status == "arp-scan succeed", data)
        dups = [(time, mean(n)) for (time, n) in groupby(x->x.timestamp[1:11], (x, y) -> push!(x, y.duplicates), ()->i64[], hosts)]
        hosts = [(time, mean(n)) for (time, n) in groupby(x->x.timestamp[1:11], (x, y) -> push!(x, y.hosts), ()->i64[], hosts)]

        @json """{
            backgroundColor: 'transparent',
            title: { text: 'Users' },
            xAxis: { type: 'category' },
            yAxis: { type: 'value' },
            legend: {},
            tooltip: { trigger: 'axis' },
            dataZoom: [{
                type: 'slider',
                start: 60,
                height: 20,
                bottom: 12
            }],
            series: [{
                name: 'hosts',
                type: 'line',
                data: $(sort(hosts)),
                smooth: true
            }, {
                name: 'ip duplicates',
                type: 'line',
                data: $(sort(dups)),
                smooth: true
            }]
        }"""
    end

    conn, speed, dns, hosts, [plot1, plot2, plot3]
end

import Restful.template

const app = Restful.app()

app.get("/", template) do req, res, route
    conn, speed, dns, hosts, plots = get_info()
    res.render("monitor.jlt", time=Dates.format(now(), "yyyy-mm-dd HH:MM:SS"), conn=conn, speed=speed, dns=dns, hosts=hosts, plots=plots, randstring=randstring)
end

@main function main(port::Int=8080)
    app.listen("0.0.0.0", port)
end