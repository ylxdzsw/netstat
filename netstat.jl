using JSON2
using Dates
using Base64
using Sockets
using OhMyJulia

import Base.adjoint # monky patch
adjoint(x::Unsigned) = ntoh(x)

const list = [
    "sustc.edu.cn",
    "scholar.google.com.hk",
    "stackoverflow.com",
    "en.wikipedia.org"
]

msg(;x...) = lock(stdout) do
    JSON2.write(stdout, (timestamp=Dates.format(now(), "mm.dd HH:MM:SS"), x...))
    stdout << '\n'
end

function pack_dns_query(website, id::u16=rand(u16))
    buf = IOBuffer()
    buf << asbytes(id') << asbytes(0b0_0000_0_0_1_0_000_0000')

    buf << asbytes(0x0001') << asbytes(0x0000) << asbytes(0x0000) << asbytes(0x0000)
    
    qname = mapreduce(++, split(website, '.')) do seg
        l = length(seg)
        (l % u8) ++ Bytes(seg)
    end
    buf << qname << asbytes(0x00) << asbytes(0x0001') << asbytes(0x0001') >> take!
end

function get_default_dns_linux()
    first(cadr(split(line)) for line in eachline("/etc/resolv.conf") if startswith(line, "nameserver"))
end

function test_dns(target=rand(list), dns=get_default_dns_linux())
    socket = UDPSocket()
    starttime = time()

    @async try
        send(socket, IPv4(dns), 53, pack_dns_query(target))
        result = recv(socket)
        msg(
            status = "dns succeed",
            website = target,
            dns = dns,
            elapsed = time() - starttime,
            result = base64encode(result)
        )
    catch e
        msg(
            status = "dns failed",
            website = target,
            dns = dns,
            elapsed = time() - starttime,
            error = string(e)
        )
    end

    @async begin
        sleep(5)
        close(socket)
    end
end

function test_ping(target=rand(list))
    starttime = time()

    @async try
        connect(target, 443) |> close
        msg(
            status = "ping succeed",
            website = target,
            elapsed = time() - starttime
        )
    catch e
        msg(
            status = "ping failed",
            website = target,
            elapsed = time() - starttime,
            error = string(e)
        )
    end
end

function test_speed()
    starttime = time()
    p = run(pipeline(`node speedtest.js`, stdout=Pipe()), wait=false)

    @async try
        wait(p)
        if p.exitcode != 0 || p.termsignal != 0
            error("speedtest.js exit with code $(p.exitcode)")
        end

        close(p.out.in)
        result = read(p.out, String)
        json = JSON2.read(result)
        msg(
            status = "speedtest succeed",
            download = json.speeds.download,
            upload = json.speeds.upload,
            ping = json.server.ping,
            elapsed = time() - starttime,
            result = result
        )
    catch e
        msg(
            status = "speedtest failed",
            elapsed = time() - starttime,
            error = string(e)
        )
    end

    @async begin
        sleep(180)
        kill(p)
    end
end

function test_arp()
    starttime = time()
    p = run(pipeline(`sudo arp-scan -l`, stdout=Pipe()), wait=false)

    @async try
        wait(p)
        if p.exitcode != 0 || p.termsignal != 0
            error("arp-scan exit with code $(p.exitcode)")
        end

        close(p.out.in)
        result = read(p.out, String)
        msg(
            status = "arp-scan succeed",
            hosts = count(x->x=='\t', result) ÷ 2,
            duplicates = count(x->true, eachmatch(r"D[uU][pP]", result)),
            elapsed = time() - starttime,
            result = result
        )
    catch e
        msg(
            status = "arp-scan failed",
            elapsed = time() - starttime,
            error = string(e)
        )
    end

    @async begin
        sleep(5)
        kill(p)
    end
end

while true
    t = floor(Int, time())
    sleep(t + 1.001 - time())

    t % 2 == 0    && test_dns()
    t % 2 == 1    && test_ping()
    t % 30 == 0   && test_arp()
    t % 1800 == 0 && test_speed()

    t % 15 == 0 && flush(stdout)
end
