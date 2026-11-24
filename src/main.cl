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
    println(" -H, --header <header>      Pass custom header to server")
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
    println(" -b, --cookie <data|file>   Pass cookie string or file to server")
    println(" -c, --cookie-jar <file>    Save response cookies to file")
    println(" -k, --insecure             Allow insecure SSL connections")
    println(" -x, --proxy <host:port>    Use specified proxy")
    println("     --oauth2-bearer <token> OAuth 2 Bearer Token")

// ------------------------------------------------------------------------------
// Function: main
// Syntax:   fn main() -> void
// Purpose:  CLI entrypoint. Parses switches, builds request, executes transfer.
// ------------------------------------------------------------------------------
fn main():
    args: vector[string] = sys_args
    if len(args) < 1:
        print_help()
        return

    let mut url_str: string = ""
    let mut method: string = "GET"
    let mut headers: vector[HttpHeader] = []
    let mut body: string = ""
    let mut verbose: int = 0
    let mut include_headers: int = 0
    let mut head_only: int = 0
    let mut follow_redirects: int = 0
    let mut output_file: string = ""
    let mut silent: int = 0
    let mut write_out: string = ""
    let mut userinfo: string = ""
    let mut cookie_data: string = ""
    let mut cookie_jar: string = ""
    let mut insecure: int = 0
    let mut proxy: string = ""
    let mut bearer_token: string = ""

    let mut i: int = 0
    let alen: int = len(args)
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
            i = i + 1
        elif (arg == "-H" or arg == "--header") and i + 1 < alen:
            h_str := args[i + 1]
            colon := -1
            let mut j: int = 0
            while j < len(h_str):
                if byte_at(h_str, j) == 58: // ':'
                    colon = j
                    j = len(h_str)
                j = j + 1
            if colon > 0:
                hk := substring(h_str, 0, colon)
                hv := ""
                vstart := colon + 1
                while vstart < len(h_str) and byte_at(h_str, vstart) == 32:
                    vstart = vstart + 1
                if vstart < len(h_str):
                    hv = substring(h_str, vstart, len(h_str) - vstart)
                headers.push(HttpHeader(hk, hv))
            i = i + 1
        elif (arg == "-d" or arg == "--data" or arg == "--data-raw") and i + 1 < alen:
            body = args[i + 1]
            if method == "GET":
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
        elif arg == "-k" or arg == "--insecure":
            insecure = 1
        elif (arg == "-b" or arg == "--cookie") and i + 1 < alen:
            cookie_data = args[i + 1]
            i = i + 1
        elif (arg == "-c" or arg == "--cookie-jar") and i + 1 < alen:
            cookie_jar = args[i + 1]
            i = i + 1
        elif (arg == "-x" or arg == "--proxy") and i + 1 < alen:
            proxy = args[i + 1]
            i = i + 1
        elif arg == "--oauth2-bearer" and i + 1 < alen:
            bearer_token = args[i + 1]
            i = i + 1
        elif (arg == "-u" or arg == "--user") and i + 1 < alen:
            userinfo = args[i + 1]
            i = i + 1
        elif (arg == "-o" or arg == "--output") and i + 1 < alen:
            output_file = args[i + 1]
            i = i + 1
        elif arg == "-s" or arg == "--silent":
            silent = 1
        elif (arg == "-w" or arg == "--write-out") and i + 1 < alen:
            write_out = args[i + 1]
            i = i + 1
        elif len(arg) > 0 and byte_at(arg, 0) != 45: // not '-'
            url_str = arg
        i = i + 1

    if len(url_str) == 0:
        if silent == 0:
            println("curl: no URL specified!")
            println("curl: try 'cluster-curl --help' for more information")
        return

    parsed_u := parse_url(url_str)
    if len(userinfo) > 0:
        parsed_u.userinfo = userinfo

    req := HttpRequest(method, parsed_u, headers, body, cookie_data, bearer_token)
    opts := TransferOptions(verbose, include_headers, head_only, follow_redirects, 10, output_file, silent, write_out, cookie_data, cookie_jar, insecure, proxy, bearer_token)

    res := execute_transfer(req, opts, 0)

    if include_headers == 1 or head_only == 1:
        crlf := chr(13) + chr(10)
        println(res.headers_raw + crlf)

    if head_only == 0:
        if len(output_file) > 0:
            file_write(output_file, res.body)
        else:
            print(res.body)

    if len(write_out) > 0:
        summary := format_write_out(write_out, res)
        print(summary)
