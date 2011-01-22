#
# File: emio.b
#
# This file contains the implementation of the EMIO module.
# This implementation uses the Post Office Protocol (Version 3)
# POP3 to access an email server.
#
 
 
implement EMIO;
 
include "sys.m";
sys: Sys;
FD, Connection: import sys;
 
connect : Connection;
isOpen : int;
 
 
# some useful constants.
ERR:     con 0;
OK:      con 1;
CR:     con 13;
LF:     con 10;
DOT:    con 46;
CRLF :  con "\r\n";

DELIMETER : con "\n";
 
 
 
include "emio.m";
 
 
 
 
init()
{
        # Load the sys module and set the connection status
        # to not open.
        sys = load Sys Sys->PATH;
        isOpen = 0;
}
 
 
 
 
open(ipaddr : string,
     username : string,
     password : string) : (int, string)
{
        success : int;
        resp : string;
        cmd : string;
 
        # Is the connection to the email server open?
        if (isOpen)
                return (0, "Connection is already open.");
 
        # Start IP Network Services.
        #sys->bind("#I", "/net", sys->MAFTER);
        (success, connect) = sys->dial (ipaddr, nil);
        if (success <= 0) {
		s := "Failed when dialing address " + ipaddr;
                return (0, s);
	}
 
        # Get the POP3 server's greeting.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (0, "Server did not send proper greeting");
 
        # Issue the USER command.
        cmd = "USER " + username + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (0, "Failed when sending command to server.");
 
        # Get the response for the USER command.
        (success, resp) = readresponse(connect.dfd);
        if (!success) {
                cmd = "QUIT" + CRLF;
                success = sendcommand(connect.dfd, cmd);
                return (0, resp);
        }
 
        # Issue the PASS command.
        cmd = "PASS " + password + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (0, "Failed when sending command to server.");
 
        # Get the response for the PASS command.
        (success, resp) = readresponse(connect.dfd);
        if (!success) {
                cmd = "QUIT" + CRLF;
                success = sendcommand(connect.dfd, cmd);
                return (0, resp);
        }
 
        # Total success!
        isOpen = 1;
        return (1, nil);
}
 
 
 
 
numberofmessages() : (int, string)
{
        # Is the connection to the email server open?
        if (!isOpen)
                return (-1, "no connection to mailbox");
 
        success : int;
        resp : string;
        cmd : string;
 
        # Issue the STAT command.
        cmd = "STAT" + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (-1, "failed to send STAT command");
 
        # Get the response for the STAT command.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (-1, resp);
 
        # The response for a STAT command contains to integers.
        # The first is the number of messages.
        total : int;
        paramlist : list of string;
        (total, paramlist) = sys->tokenize(resp, " ");
        if (total < 1)
                return (-1, "bad arguments return from STAT command");
        total = int (hd paramlist);
 
        # Total success!
        return (total, nil);
}

#
# FUNCTION:	messagelength()
#
# PURPOSE:	provides number of octets in a specified message
#		NOTE: the LIST command may be used to get information
#		about all messages, but this is NOT implemented here
#		EXAMPLES: (C - client, S - server)
#			C: LIST 2
#			S: +OK 2 200
#			S: .
#
#			C: LIST 3
#			S: -ERR no such message, only 2 messages in maildrop
#			S: .
#
#
messagelength (num : int) : (int, string)
{
	# Is the connection to the email server open?
        if (!isOpen)
                return (-1, "no connection to mailbox");
 
        success : int;
        resp : string;
        cmd : string;
 
        # Issue the LIST command.
	if (num < 0) 
        	return (-1, "LIST: incorrect message number specified");
	else 
		cmd = "LIST " + string num + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (-1, "failed to send LIST command");
 
        # Get the response for the LIST command.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (-1, resp);
 
        # The response for a LIST command contains two integers
	# The first token is always an integer
        n, octets : int;
        paramlist : list of string;
        (n, paramlist) = sys->tokenize(resp, " ");
        if (n < 1)
                return (-1, "bad arguments return from LIST command");
	paramlist = tl paramlist;
        octets = int (hd paramlist);
 
        # Total success!
        return (octets, nil);
}
 
 
messagetext(messagenumber : int) : (int, string, list of string)
{
        success : int;
        resp : string;
        cmd : string;
 
        # Is the connection to the email server open?
        if (!isOpen)
                return (0, "no connection to mailbox", nil);
 
        # Issue the RETR command.
        cmd = "RETR " + itoa(messagenumber) + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (0, "failed to send RETR command", nil);
 
        # Get the response for the RETR command.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (0, resp, nil);
 
        # Get the message text.
        text : list of string;
        (success, text) = readmessagetext(connect.dfd);
        if (!success)
                return (0, "failed to read message text", nil);
 
        # Total success!
        return (1, nil, text);
}
 
 

# This function returns STRING rather than list of STRING
msgtextstring (num : int) : (int, string, string)
{
        success : int;
        resp : string;
        cmd : string;
 
        # Is the connection to the email server open?
        if (!isOpen)
                return (0, "no connection to mailbox", nil);
 
        # Issue the RETR command.
        cmd = "RETR " + itoa(num) + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (0, "failed to send RETR command", nil);
 
        # Get the response for the RETR command.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (0, resp, nil);
 
        # Get the message text.
        text : string;
        (success, text) = readmsgtextstring (connect.dfd);
        if (!success)
                return (0, "failed to read message text", nil);
 
        # Total success!
        return (1, nil, text);
}
 
 
deletemessage(messagenumber : int) : (int, string)
{
        success : int;
        resp : string;
        cmd : string;
 
        # Is the connection to the email server open?
        if (!isOpen)
                return (0, "no connection to mailbox");
 
        # Issue the DELE command.
        cmd = "DELE " + itoa(messagenumber) + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (0, "failed to send DELE command");
 
        # Get the response for the DELE command.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (0, resp);
 
        # Total success!
        return (1, nil);
}
 
 
 
 
reset() : (int, string)
{
        success : int;
        resp : string;
        cmd : string;
 
        # Is the connection to the email server open?
        if (!isOpen)
                return (0, "Connection is not open.");
 
        # Issue the RSET command.
        cmd = "RSET" + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (0, "Failed when sending command to server.");
 
        # Get the response for the RSET command.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (0, resp);
 
        # Total success!
        return (1, nil);
}
 
 
 
 
 
close() : (int, string)
{
        success : int;
        resp : string;
        cmd : string;
 
        # Is the connection to the email server open?
        if (!isOpen)
                return (0, "Connection is not open.");
 
        # Issue the QUIT command.
        cmd = "QUIT" + CRLF;
        success = sendcommand(connect.dfd, cmd);
        if (!success)
                return (0, "Failed when sending command to server.");
 
        # Get the response for the QUIT command.
        (success, resp) = readresponse(connect.dfd);
        if (!success)
                return (0, resp);
 
        # Total success!
        isOpen = 0;
        return (1, nil);
}
 
 
 
 
 
readresponse(io: ref FD) : (int, string)
{
        # Read a line (up to CRLF) from the io file.
        (success, line) := readline(io);
        if (!success)
                return (0, "Could not read from server");
 
        #
        # Examine the response string for a positive ("+OK")
        # or negative ("-ERR) response.
        #
        if ((len line >= 3) && (line[0:3] == "+OK")) {
                # A positive response was recieved, is
                # there any additional information?
                if (len line >= 5)
                        return (OK, line[4:len line-1]);
                else
                        return (OK, nil);
        }
 
        if ((len line >= 4) && (line[0:4] == "-ERR")) {
                # A negative response was recieved, is
                # there any additional information?
                if (len line >= 6)
                        return (ERR, line[5:len line-1]);
                else
                        return (ERR, nil);
        }
 
        # Did not recognize the response.
        return (ERR, nil);
}
 
 
 
 
 
readmessagetext(io : ref FD) : (int, list of string)
{
        # Read all the lines in the message.
        # The last line is indicated by a "." and a CRLF.
        text : list of string;
        temp : list of string;
        str : string;
        do {
                # Read a line (up to CRLF) from the io file.
                (success, line) := readline(io);
                if (!success)
                        return (0, nil);
 
                i, n : int;
                (n, text) = sys->tokenize(line, "\n");
                for (i=0; i<n; i++) {
                        str = hd text;
                        if (text != nil)
                                text = tl text;
                        if (str[0:1] == ".")
                                str = str[1:len str - 1];
                        temp = str :: temp;
                }
 
                # reverse the list.
                text = nil;
                for (i=0; i<n; i++) {
                        str = hd temp;
                        if (temp != nil)
                                temp = tl temp;
                        text = str :: text;
                }
 
                if ((line[len line - 3] == DOT) &&
                    (line[len line - 2] == CR) &&
                    (line[len line - 1] == LF))
                        break;
        } while (1);
 
        return (1, text);
}
 
 
 
# This function returns a STRING rather than list of STRING 
readmsgtextstring (io : ref FD) : (int, string)
{
        # Read all the lines in the message.
        # The last line is indicated by a "." and a CRLF.
        text : list of string;
        temp : list of string;
        str : string;
        do {
                # Read a line (up to CRLF) from the io file.
                (success, line) := readline(io);
                if (!success)
                        return (0, nil);
 
                i, n : int;
                (n, text) = sys->tokenize(line, "\n");
                for (i=0; i<n; i++) {
                        str = hd text;
                        if (text != nil)
                                text = tl text;
                        if (str[0:1] == ".")
                                str = str[1:len str - 1];
                        temp = str :: temp;
                }
 
                # reverse the list.
                text = nil;
                for (i=0; i<n; i++) {
                        str = hd temp;
                        if (temp != nil)
                                temp = tl temp;
                        text = str :: text;
                }
 
                if ((line[len line - 3] == DOT) &&
                    (line[len line - 2] == CR) &&
                    (line[len line - 1] == LF))
                        break;
        } while (1);

	rettext : string; rettext = nil;
	k := len text;
	for (i := 1; i < k; i++) {
		slice := hd text;
		rettext = rettext + DELIMETER + slice[0:len slice - 1];
		text = tl text;
	} 

        return (1, rettext);
}
 
readline(io: ref FD) : (int, string)
{
        r : int;
        line : string;
        buf := array[8192] of byte;
 
        #
        # Read up to the CRLF
        #
        line = "";
        for(;;) {
                r = sys->read(io, buf, len buf);
                if(r <= 0)
                        return (ERR, nil);
 
                line += string buf[0:r];
                if ((len line >= 2) &&
                    (line[len line-2] == CR) &&
                    (line[len line-1] == LF))
                        break;
        }
 
        # Total success!
        return (1, line);
}
 
 
 
 
 
sendcommand(io: ref FD, cmd : string) : int
{
        bytes : int;
        bytes = sys->write(io, array of byte(cmd), len cmd);
        return (bytes == len cmd);
}
 
 
 
 
itoa(number : int) : string
{
        map : con "0123456789";
        text : string;
        value : int = number;
        rem : int;
        t := array[1] of byte;
 
        while (value != 0) {
                rem = value % 10;
                t[0] = byte map[rem];
                text = string t + text;
                value = value / 10;
        }
        return text;
}

