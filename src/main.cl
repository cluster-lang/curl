// ==============================================================================
// Module:      Main CLI Command-Line Driver (main.cl)
// Project:     Cluster cURL (High-Performance Network Transfer Client)
// Author:      zk-mohammad <ZaidKhan-alamgir@proton.me>
// License:     Cluster Community & Fair-Source License (CCFL v2.0)
// Description: Command-line interface parser, flag evaluator, write-out formatter,
//              and execution pipeline for Cluster cURL.
// ==============================================================================

import "src/url.cl"
import "src/http.cl"
import "src/response.cl"
import "src/client.cl"

// ------------------------------------------------------------------------------
// Function: split_lines
// Syntax:   fn split_lines(text: string) -> vector[string]
// Purpose:  Splits a multiline string into individual lines delimited by LF (with CR stripped).
// ------------------------------------------------------------------------------
fn split_lines(text: string) -> vector[string]:
    lines: vector[string] = []
    cur := ""
    tlen := len(text)
    i := 0
    while i < tlen:
        b := byte_at(text, i)
        if b == 10:
            lines.push(cur)
            cur = ""
        elif b != 13:
            cur = cur + chr(b)
        i = i + 1

    if len(cur) > 0:
        lines.push(cur)

    return lines

// ------------------------------------------------------------------------------
// Function: print_help
// Syntax:   fn print_help() -> void
// Purpose:  Displays usage syntax, available command-line switches, and descriptions.
// ------------------------------------------------------------------------------
fn print_help():
    println("Usage: cluster-curl [options...] <url>")
    println("Cluster High-Performance cURL Client (LLVM -O3)\n")
    println("Options:")
    println(" -d, --data <data>          HTTP POST data")
    println(" -H, --header <header/@file> Pass custom header(s) to server")
    println(" -h, --help                 This help text")
    println(" -I, --head                 Show document info only (HEAD request)")
    println(" -i, --include              Include protocol response headers in the output")
    println(" -L, --location             Follow redirects")
    println(" -o, --output <file>        Write to file instead of stdout")
    println(" -s, --silent               Silent mode")
    println(" -u, --user <user:password> Server user and password")
    println(" -v, --verbose              Make the operation more talkative")
    println(" -V, --version              Show version number and quit")
    println(" -w, --write-out <format>   Use output FORMAT after completion")
    println(" -X, --request <command>    Specify request command to use")

// ------------------------------------------------------------------------------
// Function: format_write_out
// Syntax:   fn format_write_out(fmt: string, res: HttpResponse) -> string
// Purpose:  Interpolates format variables (%{http_code}, %{content_type}, etc.)
//           and escape sequences into custom output summary strings.
// ------------------------------------------------------------------------------
fn format_write_out(fmt: string, res: HttpResponse) -> string:
    out := ""
    i := 0
    flen := len(fmt)
    while i < flen:
        if i + 1 < flen and byte_at(fmt, i) == 37 and byte_at(fmt, i + 1) == 123: // "%{"
            close_pos := -1
            j := i + 2
            while j < flen:
                if byte_at(fmt, j) == 125: // '}'
                    close_pos = j
                    j = flen
                j = j + 1

            if close_pos > 0:
                var_name := substring(fmt, i + 2, close_pos - (i + 2))
                if var_name == "http_code":
                    out = out + res.status_code
                elif var_name == "content_type":
                    out = out + get_response_header(res, "content-type")
                elif var_name == "size_download":
                    out = out + len(res.body)
                elif var_name == "time_total":
                    out = out + "0.001"
                i = close_pos + 1
            else:
                out = out + chr(byte_at(fmt, i))
                i = i + 1
        elif i + 1 < flen and byte_at(fmt, i) == 92 and byte_at(fmt, i + 1) == 110: // "\n"
            out = out + chr(10)
            i = i + 2
        else:
            out = out + chr(byte_at(fmt, i))
            i = i + 1
    return out

// ------------------------------------------------------------------------------
// Function: main
// Syntax:   fn main() -> void
// Purpose:  CLI entrypoint. Parses command line switches, executes HTTP transactions,
//           and prints formatted response headers, payload, and write-out metrics.
// ------------------------------------------------------------------------------
fn main():
    args: vector[string] = sys_args
    if len(args) < 1:
        print_help()
        return

    url_str := ""
    method := "GET"
    headers: vector[HttpHeader] = []
    body := ""
    verbose := 0
    include_headers := 0
    head_only := 0
    follow_redirects := 0
    output_file := ""
    silent := 0
    write_out := ""
    userinfo := ""
    explicit_method := 0

    i := 0
    alen := len(args)
    while i < alen:
        arg := args[i]
        if arg == "-h" or arg == "--help":
            print_help()
            return
        elif arg == "-V" or arg == "--version":
            println("cluster-curl 1.0.0 (pure Cluster, LLVM -O3) libnet/1.0.0")
            println("Protocols: http https")
            println("Features: IPv6 AsynchDNS Largefile NTLM SSL TLS-SRP")
            return
        elif (arg == "-X" or arg == "--request") and i + 1 < alen:
            method = args[i + 1]
            explicit_method = 1
            i = i + 1
        elif (arg == "-H" or arg == "--header") and i + 1 < alen:
            h_str := args[i + 1]
            colon := -1
            j := 0
            while j < len(h_str):
                if byte_at(h_str, j) == 58: // ':'
                    colon = j
                    j = len(h_str)
                j = j + 1
            if colon > 0:
                k := substring(h_str, 0, colon)
                v := substring(h_str, colon + 1, len(h_str) - colon - 1)
                if len(v) > 0 and byte_at(v, 0) == 32:
                    v = substring(v, 1, len(v) - 1)
                headers.push(HttpHeader(k, v))
            i = i + 1
        elif (arg == "-d" or arg == "--data" or arg == "--data-raw" or arg == "--data-ascii") and i + 1 < alen:
            body = args[i + 1]
            if explicit_method == 0:
                method = "POST"
            i = i + 1
        elif arg == "-v" or arg == "--verbose":
            verbose = 1
        elif arg == "-i" or arg == "--include":
            include_headers = 1
        elif arg == "-I" or arg == "--head":
            head_only = 1
            method = "HEAD"
        elif arg == "-L" or arg == "--location":
            follow_redirects = 1
        elif arg == "-s" or arg == "--silent":
            silent = 1
        elif (arg == "-o" or arg == "--output") and i + 1 < alen:
            output_file = args[i + 1]
            i = i + 1
        elif (arg == "-u" or arg == "--user") and i + 1 < alen:
            userinfo = args[i + 1]
            i = i + 1
        elif (arg == "-w" or arg == "--write-out") and i + 1 < alen:
            write_out = args[i + 1]
            i = i + 1
        else:
            if len(arg) > 0 and byte_at(arg, 0) != 45: // Not a flag
                url_str = arg
        i = i + 1

    if len(url_str) == 0:
        println("curl: no URL specified!")
        println("curl: try 'cluster-curl --help' for more information")
        return

    parsed := parse_url(url_str)
    if len(userinfo) > 0:
        parsed.userinfo = userinfo

    opts := TransferOptions(verbose, include_headers, head_only, follow_redirects, 10, output_file, silent, write_out)
    req := HttpRequest(method, parsed, headers, body)

    res := execute_transfer(req, opts, 0)

    // Output formatting
    output_content := ""
    if include_headers == 1 or head_only == 1:
        output_content = res.headers_raw + chr(13) + chr(10) + chr(13) + chr(10)

    if head_only == 0:
        output_content = output_content + res.body

    if len(output_file) > 0:
        file_write(output_file, output_content)
    else:
        print(output_content)

    if len(write_out) > 0:
        formatted := format_write_out(write_out, res)
        print(formatted)
