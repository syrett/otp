%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2000-2011. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%
-module(prim_file).

%% Interface module to the file driver.



%%% Interface towards a single file's contents. Uses ?FD_DRV.

%% Generic file contents operations
-export([open/2, open/3, close/1, close/2,
         datasync/1, datasync/2, sync/1, sync/2,
         advise/4, advise/5,
         position/2, position/3, truncate/1, truncate/2,
	 write/2, write/3, pwrite/2, pwrite/3, pwrite/4,
         read/2, read/3, read_line/1, read_line/2,
         pread/2, pread/3, pread/4, copy/3, copy/4]).

%% Specialized file operations
-export([open/1]).
-export([read_file/1, read_file/2, read_file/3, write_file/2, write_file/3]).
-export([ipread_s32bu_p32bu/3, ipread_s32bu_p32bu/4]).



%%% Interface towards file system and metadata. Uses ?DRV.

%% Takes an optional port (opens a ?DRV port per default) as first argument.
-export([get_cwd/0, get_cwd/1, get_cwd/3,
	 set_cwd/1, set_cwd/3,
	 delete/1, delete/2, delete/3,
	 rename/2, rename/3, rename/4,
	 make_dir/1, make_dir/3,
	 del_dir/1, del_dir/3,
	 read_file_info/1, read_file_info/2, read_file_info/3,
	 altname/1, altname/3,
	 write_file_info/2, write_file_info/4,
	 make_link/2, make_link/3, make_link/4,
	 make_symlink/2, make_symlink/3, make_symlink/4,
	 read_link/1, read_link/3,
	 read_link_info/1, read_link_info/3,
	 list_dir/1, list_dir/3,
         exists/1, exists/2]).
%% How to start and stop the ?DRV port.
-export([start/0, stop/1]).

%% Debug exports
-export([open_int/4, open_int/5, open_mode/1, open_mode/4]).

%% For DTrace/Systemtap tracing
-export([get_dtrace_utag/0]).

%%%-----------------------------------------------------------------
%%% Includes and defines

-include("file.hrl").

-define(DRV,    "efile").
-define(FD_DRV, "efile").

-define(LARGEFILESIZE, (1 bsl 63)).

%% Driver commands
-define(FILE_OPEN,             1).
-define(FILE_READ,             2).
-define(FILE_LSEEK,            3).
-define(FILE_WRITE,            4).
-define(FILE_FSTAT,            5).
-define(FILE_PWD,              6).
-define(FILE_READDIR,          7).
-define(FILE_CHDIR,            8).
-define(FILE_FSYNC,            9).
-define(FILE_MKDIR,            10).
-define(FILE_DELETE,           11).
-define(FILE_RENAME,           12).
-define(FILE_RMDIR,            13).
-define(FILE_TRUNCATE,         14).
-define(FILE_READ_FILE,        15).
-define(FILE_WRITE_INFO,       16).
-define(FILE_LSTAT,            19).
-define(FILE_READLINK,         20).
-define(FILE_LINK,             21).
-define(FILE_SYMLINK,          22).
-define(FILE_CLOSE,            23).
-define(FILE_PWRITEV,          24).
-define(FILE_PREADV,           25).
-define(FILE_SETOPT,           26).
-define(FILE_IPREAD,           27).
-define(FILE_ALTNAME,          28).
-define(FILE_READ_LINE,        29).
-define(FILE_FDATASYNC,        30).
-define(FILE_ADVISE,           31).
-define(FILE_EXISTS,           32).

%% Driver responses
-define(FILE_RESP_OK,          0).
-define(FILE_RESP_ERROR,       1).
-define(FILE_RESP_DATA,        2).
-define(FILE_RESP_NUMBER,      3).
-define(FILE_RESP_INFO,        4).
-define(FILE_RESP_NUMERR,      5).
-define(FILE_RESP_LDATA,       6).
-define(FILE_RESP_N2DATA,      7).
-define(FILE_RESP_EOF,         8).
-define(FILE_RESP_FNAME,       9).
-define(FILE_RESP_ALL_DATA,   10).
-define(FILE_RESP_LFNAME,     11).

%% Open modes for the driver's open function.
-define(EFILE_MODE_READ,       1).
-define(EFILE_MODE_WRITE,      2).
-define(EFILE_MODE_READ_WRITE, 3).  
-define(EFILE_MODE_APPEND,     4).
-define(EFILE_COMPRESSED,      8).
-define(EFILE_MODE_EXCL,       16).

%% Use this mask to get just the mode bits to be passed to the driver.
-define(EFILE_MODE_MASK, 31).

%% Seek modes for the driver's seek function.
-define(EFILE_SEEK_SET, 0).
-define(EFILE_SEEK_CUR, 1).
-define(EFILE_SEEK_END, 2).

%% Options
-define(FILE_OPT_DELAYED_WRITE, 0).
-define(FILE_OPT_READ_AHEAD,    1).

%% IPREAD variants
-define(IPREAD_S32BU_P32BU, 0).

%% POSIX file advises
-define(POSIX_FADV_NORMAL,     0).
-define(POSIX_FADV_RANDOM,     1).
-define(POSIX_FADV_SEQUENTIAL, 2).
-define(POSIX_FADV_WILLNEED,   3).
-define(POSIX_FADV_DONTNEED,   4).
-define(POSIX_FADV_NOREUSE,    5).


%%%-----------------------------------------------------------------
%%% Functions operating on a file through a handle. ?FD_DRV.
%%%
%%% Generic file contents operations.
%%%
%%% Supposed to be called by applications through module file.


%% Opens a file. Returns {error, Reason} | {ok, FileDescriptor}.
open(File, ModeList) ->
    open(File, ModeList, get_dtrace_utag()).

open(File, ModeList, DTraceUtag)
  when (is_list(File) orelse is_binary(File)),
       is_list(ModeList),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    case open_mode(ModeList) of
	{Mode, Portopts, Setopts} ->
	    open_int({?FD_DRV, Portopts}, File, Mode, Setopts, DTraceUtag);
	Reason ->
	    {error, Reason}
    end;
open(_, _, _) ->
    {error, badarg}.

%% Opens a port that can be used for open/3 or read_file/2.
%% Returns {ok, Port} | {error, Reason}.
open(Portopts) when is_list(Portopts) ->
    case drv_open(?FD_DRV, Portopts) of
	{error, _} = Error ->
	    Error;
	Other ->
	    Other
    end;
open(_) ->
    {error, badarg}.

open_int(Arg, File, Mode, Setopts) ->
    open_int(Arg, File, Mode, Setopts, get_dtrace_utag()).

open_int({Driver, Portopts}, File, Mode, Setopts, DTraceUtag) ->
    %% TODO: add DTraceUtag to drv_open()?
    case drv_open(Driver, Portopts) of
	{ok, Port} ->
	    open_int(Port, File, Mode, Setopts, DTraceUtag);
	{error, _} = Error ->
	    Error
    end;
open_int(Port, File, Mode, Setopts, DTraceUtag) ->
    M = Mode band ?EFILE_MODE_MASK,
    case drv_command(Port, [<<?FILE_OPEN, M:32>>,
                            pathname(File), enc_utag(DTraceUtag)]) of
	{ok, Number} ->
	    open_int_setopts(Port, Number, Setopts, DTraceUtag);
	Error ->
	    drv_close(Port),
	    Error
    end.

open_int_setopts(Port, Number, [], _DTraceUtag) ->
    {ok, #file_descriptor{module = ?MODULE, data = {Port, Number}}};    
open_int_setopts(Port, Number, [Cmd | Tail], DTraceUtag) ->
    case drv_command(Port, [Cmd, enc_utag(DTraceUtag)]) of
	ok ->
	    open_int_setopts(Port, Number, Tail, DTraceUtag);
	Error ->
	    drv_close(Port),
	    Error
    end.



%% Returns ok.

close(Arg) ->
    close(Arg, get_dtrace_utag()).

close(#file_descriptor{module = ?MODULE, data = {Port, _}}, DTraceUtag)
  when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    case drv_command(Port, [<<?FILE_CLOSE>>, enc_utag(DTraceUtag)]) of
	ok ->
	    drv_close(Port);
	Error ->
	    Error
    end;
%% Closes a port opened with open/1.
close(Port, _DTraceUtag) when is_port(Port) ->
    drv_close(Port).

-define(ADVISE(Offs, Len, Adv, BUtag),
	<<?FILE_ADVISE, Offs:64/signed, Len:64/signed,
	  Adv:32/signed, BUtag/binary>>).

%% Returns {error, Reason} | ok.
advise(FD, Offset, Length, Advise) ->
    advise(FD, Offset, Length, Advise, get_dtrace_utag()).

advise(#file_descriptor{module = ?MODULE, data = {Port, _}},
       Offset, Length, Advise, DTraceUtag)
  when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    BUtag = term_to_binary(enc_utag(DTraceUtag)),
    case Advise of
	normal ->
	    Cmd = ?ADVISE(Offset, Length, ?POSIX_FADV_NORMAL, BUtag),
	    drv_command(Port, Cmd);
	random ->
	    Cmd = ?ADVISE(Offset, Length, ?POSIX_FADV_RANDOM, BUtag),
	    drv_command(Port, Cmd);
	sequential ->
	    Cmd = ?ADVISE(Offset, Length, ?POSIX_FADV_SEQUENTIAL, BUtag),
	    drv_command(Port, Cmd);
	will_need ->
	    Cmd = ?ADVISE(Offset, Length, ?POSIX_FADV_WILLNEED, BUtag),
	    drv_command(Port, Cmd);
	dont_need ->
	    Cmd = ?ADVISE(Offset, Length, ?POSIX_FADV_DONTNEED, BUtag),
	    drv_command(Port, Cmd);
	no_reuse ->
	    Cmd = ?ADVISE(Offset, Length, ?POSIX_FADV_NOREUSE, BUtag),
	    drv_command(Port, Cmd);
	_ ->
	    {error, einval}
    end.

%% Returns {error, Reason} | ok.
write(Desc, Bytes) ->
    write(Desc, Bytes, get_dtrace_utag()).

write(#file_descriptor{module = ?MODULE, data = {Port, _}}, Bytes, DTraceUtag)
  when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    %% This is rare case where DTraceUtag is not at end of command list.
    case drv_command(Port, [?FILE_WRITE,enc_utag(DTraceUtag),Bytes]) of
	{ok, _Size} ->
	    ok;
	Error ->
	    Error
    end.

%% Returns ok | {error, {WrittenCount, Reason}}
pwrite(#file_descriptor{module = ?MODULE, data = {Port, _}}, L)
  when is_list(L) ->
    pwrite_int(Port, L, 0, [], [], get_dtrace_utag()).

pwrite_int(_, [], 0, [], [], _DTraceUtag) ->
    ok;
pwrite_int(Port, [], N, Spec, Data, DTraceUtag) ->
    Header = list_to_binary([<<?FILE_PWRITEV>>, enc_utag(DTraceUtag),
                             <<N:32>>, reverse(Spec)]),
    case drv_command_raw(Port, [Header | reverse(Data)]) of
	{ok, _Size} ->
	    ok;
	Error ->
	    Error
    end;
pwrite_int(Port, [{Offs, Bytes} | T], N, Spec, Data, DTraceUtag)
  when is_integer(Offs) ->
    if
	-(?LARGEFILESIZE) =< Offs, Offs < ?LARGEFILESIZE ->
	    pwrite_int(Port, T, N, Spec, Data, Offs, Bytes, DTraceUtag);
	true ->
	    {error, einval}
    end;
pwrite_int(_, [_|_], _N, _Spec, _Data, _DTraceUtag) ->
    {error, badarg}.

pwrite_int(Port, T, N, Spec, Data, Offs, Bin, DTraceUtag)
  when is_binary(Bin) ->
    Size = byte_size(Bin),
    pwrite_int(Port, T, N+1, 
	       [<<Offs:64/signed, Size:64>> | Spec], 
	       [Bin | Data], DTraceUtag);
pwrite_int(Port, T, N, Spec, Data, Offs, Bytes, DTraceUtag) ->
    try list_to_binary(Bytes) of
	Bin ->
	    pwrite_int(Port, T, N, Spec, Data, Offs, Bin, DTraceUtag)
    catch
	error:Reason ->
	    {error, Reason}
    end.



%% Returns {error, Reason} | ok.
pwrite(#file_descriptor{module = ?MODULE, data = {Port, _}}, L, DTraceUtag)
  when is_list(L),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    pwrite_int(Port, L, 0, [], [], DTraceUtag);

pwrite(#file_descriptor{module = ?MODULE, data = {Port, _}}, Offs, Bytes)
  when is_integer(Offs) ->
    pwrite_int2(Port, Offs, Bytes, get_dtrace_utag());
pwrite(#file_descriptor{module = ?MODULE}, _, _) ->
    {error, badarg}.

pwrite(#file_descriptor{module = ?MODULE, data = {Port, _}}, Offs, Bytes, DTraceUtag)
  when is_integer(Offs),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    pwrite_int2(Port, Offs, Bytes, DTraceUtag);
pwrite(#file_descriptor{module = ?MODULE}, _, _, _DTraceUtag) ->
    {error, badarg}.

pwrite_int2(Port, Offs, Bytes, DTraceUtag) ->
    if
	-(?LARGEFILESIZE) =< Offs, Offs < ?LARGEFILESIZE ->
	    case pwrite_int(Port, [], 0, [], [], Offs, Bytes, DTraceUtag) of
		{error, {_, Reason}} ->
		    {error, Reason};
		Result ->
		    Result
	    end;
	true ->
	    {error, einval}
    end.

%% Returns {error, Reason} | ok.
datasync(FD) ->
    datasync(FD, get_dtrace_utag()).

datasync(#file_descriptor{module = ?MODULE, data = {Port, _}}, DTraceUtag)
  when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    drv_command(Port, [?FILE_FDATASYNC, enc_utag(DTraceUtag)]).

%% Returns {error, Reason} | ok.
sync(FD) ->
    sync(FD, get_dtrace_utag()).

sync(#file_descriptor{module = ?MODULE, data = {Port, _}}, DTraceUtag)
  when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    drv_command(Port, [?FILE_FSYNC, enc_utag(DTraceUtag)]).

%% Returns {ok, Data} | eof | {error, Reason}.
read_line(FD) ->
    read_line(FD, get_dtrace_utag()).

read_line(#file_descriptor{module = ?MODULE, data = {Port, _}}, DTraceUtag) ->
    case drv_command(Port, [<<?FILE_READ_LINE>>, enc_utag(DTraceUtag)]) of
	{ok, {0, _Data}} ->
	    eof;
	{ok, {_Size, Data}} ->
	    {ok, Data};
	{error, enomem} ->
	    erlang:garbage_collect(),
	    case drv_command(Port, <<?FILE_READ_LINE>>) of
		{ok, {0, _Data}} ->
		    eof;
		{ok, {_Size, Data}} ->
		    {ok, Data};
		Other ->
		    Other
	    end;
	Error ->
	    Error
    end.
	
%% Returns {ok, Data} | eof | {error, Reason}.
read(FD, Size) ->
    read(FD, Size, get_dtrace_utag()).

read(#file_descriptor{module = ?MODULE, data = {Port, _}}, Size, DTraceUtag)
  when is_integer(Size),
       0 =< Size,
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    if
	Size < ?LARGEFILESIZE ->
	    case drv_command(Port, [<<?FILE_READ, Size:64>>,
                                    enc_utag(DTraceUtag)]) of
		{ok, {0, _Data}} when Size =/= 0 ->
		    eof;
		{ok, {_Size, Data}} ->
		    {ok, Data};
		{error, enomem} ->
		    %% Garbage collecting here might help if
		    %% the current processes have some old binaries left.
		    erlang:garbage_collect(),
		    case drv_command(Port, [<<?FILE_READ, Size:64>>,
                                            enc_utag(DTraceUtag)]) of
			{ok, {0, _Data}} when Size =/= 0 ->
			    eof;
			{ok, {_Size, Data}} ->
			    {ok, Data};
			Other ->
			    Other
		    end;
		Error ->
		    Error
	    end;
	true ->
	    {error, einval}
    end.

%% Returns {ok, [Data|eof, ...]} | {error, Reason}
pread(#file_descriptor{module = ?MODULE, data = {Port, _}}, L)
  when is_list(L) ->
    pread_int(Port, L, 0, [], get_dtrace_utag()).

pread_int(_, [], 0, [], _DTraceUtag) ->
    {ok, []};
pread_int(Port, [], N, Spec, DTraceUtag) ->
    drv_command(Port, [<<?FILE_PREADV>>, enc_utag(DTraceUtag),
                       <<0:32, N:32>>, reverse(Spec)]);
pread_int(Port, [{Offs, Size} | T], N, Spec, DTraceUtag)
  when is_integer(Offs), is_integer(Size), 0 =< Size ->
    if
	-(?LARGEFILESIZE) =< Offs, Offs < ?LARGEFILESIZE,
	Size < ?LARGEFILESIZE ->
	    pread_int(Port, T, N+1, [<<Offs:64/signed, Size:64>> | Spec],
                      DTraceUtag);
	true ->
	    {error, einval}
    end;
pread_int(_, [_|_], _N, _Spec, _DTraceUtag) ->
    {error, badarg}.

%% Returns {ok, Data} | eof | {error, Reason}.
pread(#file_descriptor{module = ?MODULE, data = {Port, _}}, L, DTraceUtag)
  when is_list(L),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    pread_int(Port, L, 0, [], get_dtrace_utag());
pread(FD, Offs, Size)
  when is_integer(Offs), is_integer(Size), 0 =< Size ->
    pread(FD, Offs, Size, get_dtrace_utag()).

pread(#file_descriptor{module = ?MODULE, data = {Port, _}}, Offs, Size, DTraceUtag)
    when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    if
	-(?LARGEFILESIZE) =< Offs, Offs < ?LARGEFILESIZE,
	Size < ?LARGEFILESIZE ->
	    case drv_command(Port, 
			     [<<?FILE_PREADV>>, enc_utag(DTraceUtag),
                              <<0:32, 1:32, Offs:64/signed, Size:64>>]) of
		{ok, [eof]} ->
		    eof;
		{ok, [Data]} ->
		    {ok, Data};
		Error ->
		    Error
	    end;
	true ->
	    {error, einval}
    end;
pread(_, _, _, _) ->
    {error, badarg}.



%% Returns {ok, Position} | {error, Reason}.
position(FD, At) ->
    position(FD, At, get_dtrace_utag()).

position(#file_descriptor{module = ?MODULE, data = {Port, _}}, At, DTraceUtag)
  when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    case lseek_position(At) of
	{Offs, Whence}
	when -(?LARGEFILESIZE) =< Offs, Offs < ?LARGEFILESIZE ->
	    drv_command(Port, [<<?FILE_LSEEK, Offs:64/signed, Whence:32>>,
                               enc_utag(DTraceUtag)]);
	{_, _} ->
	    {error, einval};
	Reason ->
	    {error, Reason}
    end.

%% Returns {error, Reaseon} | ok.
truncate(FD) ->
    truncate(FD, get_dtrace_utag()).

truncate(#file_descriptor{module = ?MODULE, data = {Port, _}}, DTraceUtag)
  when (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    drv_command(Port, [<<?FILE_TRUNCATE>>, enc_utag(DTraceUtag)]).



%% Returns {error, Reason} | {ok, BytesCopied}
copy(Source, Dest, Length) ->
    copy(Source, Dest, Length, get_dtrace_utag()).

copy(#file_descriptor{module = ?MODULE} = Source,
     #file_descriptor{module = ?MODULE} = Dest,
     Length, DTraceUtag)
  when is_integer(Length), Length >= 0;
       is_atom(Length),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    %% XXX Should be moved down to the driver for optimization.
    file:copy_opened(Source, Dest, Length, DTraceUtag).



ipread_s32bu_p32bu(FD, Offs, Arg) ->
    ipread_s32bu_p32bu(FD, Offs, Arg, get_dtrace_utag()).

ipread_s32bu_p32bu(#file_descriptor{module = ?MODULE,
				    data = {_, _}} = Handle,
		   Offs,
		   Infinity,
                   DTraceUtag)
  when is_atom(Infinity),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    ipread_s32bu_p32bu(Handle, Offs, (1 bsl 31)-1);
ipread_s32bu_p32bu(#file_descriptor{module = ?MODULE, data = {Port, _}},
		   Offs,
		   MaxSize,
                   DTraceUtag)
  when is_integer(Offs),
       is_integer(MaxSize),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    if
	-(?LARGEFILESIZE) =< Offs, Offs < ?LARGEFILESIZE,
	0 =< MaxSize, MaxSize < (1 bsl 31) ->
	    drv_command(Port, [<<?FILE_IPREAD, ?IPREAD_S32BU_P32BU,
                                 Offs:64, MaxSize:32>>, enc_utag(DTraceUtag)]);
	true ->
	    {error, einval}
    end;
ipread_s32bu_p32bu(#file_descriptor{module = ?MODULE, data = {_, _}},
		   _Offs,
		   _MaxSize,
                   _DTraceUtag) ->
    {error, badarg}.



%% Returns {ok, Contents} | {error, Reason}
read_file(File) when (is_list(File) orelse is_binary(File)) ->
    read_file(File, get_dtrace_utag());
read_file(_) ->
    {error, badarg}.

read_file(File, DTraceUtag)
  when (is_list(File) orelse is_binary(File)),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag))->
    case drv_open(?FD_DRV, [binary]) of
	{ok, Port} ->
	    Result = read_file(Port, File, DTraceUtag),
	    close(Port),
	    Result;
	{error, _} = Error ->
	    Error
    end;
read_file(_, _) ->
    {error, badarg}.

%% Takes a Port opened with open/1.
read_file(Port, File, DTraceUtag) when is_port(Port),
			   (is_list(File) orelse is_binary(File)) ->
    Cmd = [?FILE_READ_FILE |
           list_to_binary([pathname(File), enc_utag(DTraceUtag)])],
    case drv_command(Port, Cmd) of
	{error, enomem} ->
	    %% It could possibly help to do a 
	    %% garbage collection here, 
	    %% if the file server has some references
	    %% to binaries read earlier.
	    erlang:garbage_collect(),
	    drv_command(Port, Cmd);
	Result ->
	    Result
    end;
read_file(_,_,_) ->
    {error, badarg}.

    

%% Returns {error, Reason} | ok.
write_file(File, Bin) ->
    write_file(File, Bin, get_dtrace_utag()).

write_file(File, Bin, DTraceUtag)
  when (is_list(File) orelse is_binary(File)),
       (is_list(DTraceUtag) orelse is_binary(DTraceUtag)) ->
    OldUtag = put(dtrace_utag, DTraceUtag),     % TODO: API?
    case open(File, [binary, write]) of
	{ok, Handle} ->
	    Result = write(Handle, Bin),
	    close(Handle),
            put(dtrace_utag, OldUtag),
	    Result;
	Error ->
            put(dtrace_utag, OldUtag),
	    Error
    end;
write_file(_, _, _) ->
    {error, badarg}.
    


%%%-----------------------------------------------------------------
%%% Functions operating on files without handle to the file. ?DRV.
%%%
%%% Supposed to be called by applications through module file.



%% Returns {ok, Port}, the Port should be used as first argument in all
%% the following functions. Returns {error, Reason} upon failure.
start() ->
    try erlang:open_port({spawn, ?DRV}, [binary]) of
	Port ->
	    {ok, Port}
    catch
	error:Reason ->
	    {error, Reason}
    end.

stop(Port) when is_port(Port) ->
    try erlang:port_close(Port) of
	_ ->
	    ok
    catch
	_:_ ->
	    ok
    end.



%%% The following functions take an optional Port as first argument.
%%% If the port is not supplied, a temporary one is opened and then
%%% closed after the request has been performed.



%% get_cwd/{0,1,3}

get_cwd() ->
    get_cwd_int(0, get_dtrace_utag()).

get_cwd(Port) when is_port(Port) ->
    get_cwd_int(Port, 0, get_dtrace_utag());
get_cwd([]) ->
    get_cwd_int(0, get_dtrace_utag());
get_cwd([Letter, $: | _]) when $a =< Letter, Letter =< $z ->
    get_cwd_int(Letter - $a + 1, get_dtrace_utag());
get_cwd([Letter, $: | _]) when $A =< Letter, Letter =< $Z ->
    get_cwd_int(Letter - $A + 1, get_dtrace_utag());
get_cwd([_|_]) ->
    {error, einval};
get_cwd(_) ->
    {error, badarg}.

get_cwd(Port, [], DTraceUtag) when is_port(Port) ->
    get_cwd_int(Port, 0, DTraceUtag);
get_cwd(Port, no_drive, DTraceUtag) when is_port(Port) ->
    get_cwd_int(Port, 0, DTraceUtag);
get_cwd(Port, [Letter, $: | _], DTraceUtag)
  when is_port(Port), $a =< Letter, Letter =< $z ->
    get_cwd_int(Port, Letter - $a + 1, DTraceUtag);
get_cwd(Port, [Letter, $: | _], DTraceUtag)
  when is_port(Port), $A =< Letter, Letter =< $Z ->
    get_cwd_int(Port, Letter - $A + 1, DTraceUtag);
get_cwd(Port, [_|_], _DTraceUtag) when is_port(Port) ->
    {error, einval};
get_cwd(_, _, _DTraceUtag) ->
    {error, badarg}.

get_cwd_int(Drive, DTraceUtag) ->
    get_cwd_int({?DRV, [binary]}, Drive, DTraceUtag).

get_cwd_int(Port, Drive, DTraceUtag) ->
    drv_command(Port, list_to_binary([?FILE_PWD, Drive, enc_utag(DTraceUtag)])).



%% set_cwd/{1,3}

set_cwd(Dir) ->
    set_cwd_int({?DRV, [binary]}, Dir, get_dtrace_utag()).

set_cwd(Port, Dir, DTraceUtag) when is_port(Port) ->
    set_cwd_int(Port, Dir, DTraceUtag).

set_cwd_int(Port, Dir0, DTraceUtag) ->
    Dir = 
	(catch
	 case os:type() of
	     vxworks -> 
		 %% chdir on vxworks doesn't support
		 %% relative paths
		 %% must call get_cwd from here and use
		 %% absname/2, since
		 %% absname/1 uses file:get_cwd ...
		 case get_cwd_int(Port, 0, "") of
		     {ok, AbsPath} ->
			 filename:absname(Dir0, AbsPath);
		     _Badcwd ->
			 Dir0
		 end;
	     _Else ->
		 Dir0
	 end),
    %% Dir is now either a string or an EXIT tuple.
    %% An EXIT tuple will fail in the following catch.
    drv_command(Port, [?FILE_CHDIR, pathname(Dir), enc_utag(DTraceUtag)]).



%% delete/{1,2,3}

delete(File) ->
    delete_int({?DRV, [binary]}, File, get_dtrace_utag()).

delete(Port, File) when is_port(Port) ->
    delete_int(Port, File, get_dtrace_utag()).

delete(Port, File, DTraceUtag) when is_port(Port) ->
    delete_int(Port, File, DTraceUtag).

delete_int(Port, File, DTraceUtag) ->
    drv_command(Port, [?FILE_DELETE, pathname(File), enc_utag(DTraceUtag)]).



%% rename/{2,3,4}

rename(From, To) ->
    rename_int({?DRV, [binary]}, From, To, get_dtrace_utag()).

rename(Port, From, To) when is_port(Port) ->
    rename_int(Port, From, To, get_dtrace_utag()).

rename(Port, From, To, DTraceUtag) when is_port(Port) ->
    rename_int(Port, From, To, DTraceUtag).

rename_int(Port, From, To, DTraceUtag) ->
    drv_command(Port, [?FILE_RENAME, pathname(From), pathname(To),
                       enc_utag(DTraceUtag)]).



%% make_dir/{1,3}

make_dir(Dir) ->
    make_dir_int({?DRV, [binary]}, Dir, get_dtrace_utag()).

make_dir(Port, Dir, DTraceUtag) when is_port(Port) ->
    make_dir_int(Port, Dir, DTraceUtag).

make_dir_int(Port, Dir, DTraceUtag) ->
    drv_command(Port, [?FILE_MKDIR, pathname(Dir), enc_utag(DTraceUtag)]).



%% del_dir/{1,3}

del_dir(Dir) ->
    del_dir_int({?DRV, [binary]}, Dir, get_dtrace_utag()).

del_dir(Port, Dir, DTraceUtag) when is_port(Port) ->
    del_dir_int(Port, Dir, DTraceUtag).

del_dir_int(Port, Dir, DTraceUtag) ->
    drv_command(Port, [?FILE_RMDIR, pathname(Dir), enc_utag(DTraceUtag)]).

%% read_file_info/{1,2,3}

read_file_info(File) ->
    read_file_info_int({?DRV, [binary]}, File, get_dtrace_utag()).

read_file_info(Port, File) when is_port(Port) ->
    read_file_info_int(Port, File, get_dtrace_utag()).

read_file_info(Port, File, DTraceUtag) when is_port(Port) ->
    read_file_info_int(Port, File, DTraceUtag).

read_file_info_int(Port, File, DTraceUtag) ->
    drv_command(Port, [?FILE_FSTAT, pathname(File), enc_utag(DTraceUtag)]).

%% altname/{1,3}

altname(File) ->
    altname_int({?DRV, [binary]}, File, get_dtrace_utag()).

altname(Port, File, DTraceUtag) when is_port(Port) ->
    altname_int(Port, File, DTraceUtag).

altname_int(Port, File, DTraceUtag) ->
    drv_command(Port, [?FILE_ALTNAME, pathname(File), enc_utag(DTraceUtag)]).

%% write_file_info/{2,4}

write_file_info(File, Info) ->
    write_file_info_int({?DRV, [binary]}, File, Info, get_dtrace_utag()).

write_file_info(Port, File, Info, DTraceUtag) when is_port(Port) ->
    write_file_info_int(Port, File, Info, DTraceUtag).

write_file_info_int(Port, 
		    File, 
		    #file_info{mode=Mode, 
			       uid=Uid, 
			       gid=Gid,
			       atime=Atime0, 
			       mtime=Mtime0, 
			       ctime=Ctime},
                    DTraceUtag) ->
    {Atime, Mtime} =
	case {Atime0, Mtime0} of
	    {undefined, Mtime0} -> {erlang:localtime(), Mtime0};
	    {Atime0, undefined} -> {Atime0, Atime0};
	    Complete -> Complete
	end,
    drv_command(Port, [?FILE_WRITE_INFO, 
			int_to_bytes(Mode), 
			int_to_bytes(Uid), 
			int_to_bytes(Gid),
			date_to_bytes(Atime), 
			date_to_bytes(Mtime), 
			date_to_bytes(Ctime),
			pathname(File),
                        enc_utag(DTraceUtag)]).



%% make_link/{2,3,4}

make_link(Old, New) ->
    make_link_int({?DRV, [binary]}, Old, New, get_dtrace_utag()).

make_link(Port, Old, New) when is_port(Port) ->
    make_link_int(Port, Old, New, get_dtrace_utag()).

make_link(Port, Old, New, DTraceUtag) when is_port(Port) ->
    make_link_int(Port, Old, New, DTraceUtag).

make_link_int(Port, Old, New, DTraceUtag) ->
    drv_command(Port, [?FILE_LINK, pathname(Old), pathname(New),
                       enc_utag(DTraceUtag)]).



%% make_symlink/{2,3,4}

make_symlink(Old, New) ->
    make_symlink_int({?DRV, [binary]}, Old, New, get_dtrace_utag()).

make_symlink(Port, Old, New) when is_port(Port) ->
    make_symlink_int(Port, Old, New, get_dtrace_utag()).

make_symlink(Port, Old, New, DTraceUtag) when is_port(Port) ->
    make_symlink_int(Port, Old, New, DTraceUtag).

make_symlink_int(Port, Old, New, DTraceUtag) ->
    drv_command(Port, [?FILE_SYMLINK, pathname(Old), pathname(New),
                       enc_utag(DTraceUtag)]).



%% read_link/{1,3}

read_link(Link) ->
    read_link_int({?DRV, [binary]}, Link, get_dtrace_utag()).

read_link(Port, Link, DTraceUtag) when is_port(Port) ->
    read_link_int(Port, Link, DTraceUtag).

read_link_int(Port, Link, DTraceUtag) ->
    drv_command(Port, [?FILE_READLINK, pathname(Link), enc_utag(DTraceUtag)]).



%% read_link_info/{1,3}

read_link_info(Link) ->
    read_link_info_int({?DRV, [binary]}, Link, get_dtrace_utag()).

read_link_info(Port, Link, DTraceUtag) when is_port(Port) ->
    read_link_info_int(Port, Link, DTraceUtag).

read_link_info_int(Port, Link, DTraceUtag) ->
    drv_command(Port, [?FILE_LSTAT, pathname(Link), enc_utag(DTraceUtag)]).



%% list_dir/{1,3}

list_dir(Dir) ->
    list_dir_int({?DRV, [binary]}, Dir, get_dtrace_utag()).

list_dir(Port, Dir, DTraceUtag) when is_port(Port) ->
    list_dir_int(Port, Dir, DTraceUtag).

list_dir_int(Port, Dir, DTraceUtag) ->
    drv_command(Port, [?FILE_READDIR, pathname(Dir), enc_utag(DTraceUtag)], []).



%% exists/{1,2}

exists(File) ->
    exists_int({?DRV, []}, File).

exists(Port, File) when is_port(Port) ->
    exists_int(Port, File).

exists_int(Port, File) ->
    case drv_command(Port, [?FILE_EXISTS, File, 0]) of
        ok -> true;
        {error, enoent} -> false;
        {error, eisdir} -> {error, eisdir}
    end.


%%%-----------------------------------------------------------------
%%% Functions to communicate with the driver



%% Opens a driver port and converts any problems into {error, emfile}.
%% Returns {ok, Port} when successful.

drv_open(Driver, Portopts) ->
    try erlang:open_port({spawn, Driver}, Portopts) of
	Port ->
	    {ok, Port}
    catch
	error:Reason ->
	    {error, Reason}
    end.



%% Closes a port in a safe way. Returns ok.

drv_close(Port) ->
    try erlang:port_close(Port) catch error:_ -> ok end,
    receive %% Ugly workaround in case the caller==owner traps exits
	{'EXIT', Port, _Reason} -> 
	    ok
    after 0 -> 
	    ok
    end.



%% Issues a command to a port and gets the response.
%% If Port is {Driver, Portopts} a port is first opened and 
%% then closed after the result has been received.
%% Returns {ok, Result} or {error, Reason}.

drv_command_raw(Port, Command) ->
    drv_command(Port, Command, false, undefined).

drv_command(Port, Command) ->
    drv_command(Port, Command, undefined).

drv_command(Port, Command, R) when is_binary(Command) ->
    drv_command(Port, Command, true, R);
drv_command(Port, Command, R) ->
    try erlang:iolist_size(Command) of
	_ ->
	    drv_command(Port, Command, true, R)
    catch
	error:Reason ->
	    {error, Reason}
    end.

drv_command(Port, Command, Validated, R) when is_port(Port) ->
    try erlang:port_command(Port, Command) of
	true ->
	    drv_get_response(Port, R)
    catch
	%% If the Command is valid, knowing that the port is a port,
	%% a badarg error must mean it is a dead port, that is:
	%% a currently invalid filehandle, -> einval, not badarg.
	error:badarg when Validated ->
	    {error, einval};
	error:badarg ->
	    try erlang:iolist_size(Command) of
		_ -> % Valid
		    {error, einval}
	    catch
		error:_ ->
		    {error, badarg}
	    end;
	error:Reason ->
	    {error, Reason}
    end;
drv_command({Driver, Portopts}, Command, Validated, R) ->
    case drv_open(Driver, Portopts) of
	{ok, Port} ->
	    Result = drv_command(Port, Command, Validated, R),
	    drv_close(Port),
	    Result;
	Error ->
	    Error
    end.


    
%% Receives the response from a driver port.
%% Returns: {ok, ListOrBinary}|{error, Reason}

drv_get_response(Port, R) when is_list(R) ->
    case drv_get_response(Port) of
	ok ->
	    {ok, R};
	{ok, Name} ->
	    drv_get_response(Port, [Name|R]);
	{append, Names} ->
	    drv_get_response(Port, append(Names, R));
	Error ->
	    Error
    end;
drv_get_response(Port, _) ->
    drv_get_response(Port).

drv_get_response(Port) ->
    erlang:bump_reductions(100),
    receive
	{Port, {data, [Response|Rest] = Data}} ->
	    try translate_response(Response, Rest)
	    catch
		error:Reason ->
		    {error, {bad_response_from_port, Data, 
			     {Reason, erlang:get_stacktrace()}}}
	    end;
	{'EXIT', Port, Reason} ->
	    {error, {port_died, Reason}}
    end.


%%%-----------------------------------------------------------------
%%% Utility functions.

append([I | Is], R) when is_list(R) -> append(Is, [I | R]);
append([], R) -> R.


%% Converts a list of mode atoms into a mode word for the driver.
%% Returns {Mode, Portopts, Setopts} where Portopts is a list of 
%% options for erlang:open_port/2 and Setopts is a list of 
%% setopt commands to send to the port, or error Reason upon failure.

open_mode(List) when is_list(List) ->
    case open_mode(List, 0, [], []) of
	{Mode, Portopts, Setopts} when Mode band 
			  (?EFILE_MODE_READ bor ?EFILE_MODE_WRITE) 
			  =:= 0 ->
	    {Mode bor ?EFILE_MODE_READ, Portopts, Setopts};
	Other ->
	    Other
    end.

open_mode([raw|Rest], Mode, Portopts, Setopts) ->
    open_mode(Rest, Mode, Portopts, Setopts);
open_mode([read|Rest], Mode, Portopts, Setopts) ->
    open_mode(Rest, Mode bor ?EFILE_MODE_READ, Portopts, Setopts);
open_mode([write|Rest], Mode, Portopts, Setopts) ->
    open_mode(Rest, Mode bor ?EFILE_MODE_WRITE, Portopts, Setopts);
open_mode([binary|Rest], Mode, Portopts, Setopts) ->
    open_mode(Rest, Mode, [binary | Portopts], Setopts);
open_mode([compressed|Rest], Mode, Portopts, Setopts) ->
    open_mode(Rest, Mode bor ?EFILE_COMPRESSED, Portopts, Setopts);
open_mode([append|Rest], Mode, Portopts, Setopts) ->
    open_mode(Rest, Mode bor ?EFILE_MODE_APPEND bor ?EFILE_MODE_WRITE, 
	      Portopts, Setopts);
open_mode([exclusive|Rest], Mode, Portopts, Setopts) ->
    open_mode(Rest, Mode bor ?EFILE_MODE_EXCL, Portopts, Setopts);
open_mode([delayed_write|Rest], Mode, Portopts, Setopts) ->
    open_mode([{delayed_write, 64*1024, 2000}|Rest], Mode,
	      Portopts, Setopts);
open_mode([{delayed_write, Size, Delay}|Rest], Mode, Portopts, Setopts) 
  when is_integer(Size), 0 =< Size, is_integer(Delay), 0 =< Delay ->
    if
	Size < ?LARGEFILESIZE, Delay < 1 bsl 64 ->
	    open_mode(Rest, Mode, Portopts, 
		      [<<?FILE_SETOPT, ?FILE_OPT_DELAYED_WRITE,
			Size:64, Delay:64>> 
		       | Setopts]);
	true ->
	    einval
    end;
open_mode([read_ahead|Rest], Mode, Portopts, Setopts) ->
    open_mode([{read_ahead, 64*1024}|Rest], Mode, Portopts, Setopts);
open_mode([{read_ahead, Size}|Rest], Mode, Portopts, Setopts)
  when is_integer(Size), 0 =< Size ->
    if
	Size < ?LARGEFILESIZE ->
	    open_mode(Rest, Mode, Portopts,
		      [<<?FILE_SETOPT, ?FILE_OPT_READ_AHEAD,
			Size:64>> | Setopts]);
	true ->
	    einval
    end;
open_mode([], Mode, Portopts, Setopts) ->
    {Mode, reverse(Portopts), reverse(Setopts)};
open_mode(_, _Mode, _Portopts, _Setopts) ->
    badarg.



%% Converts a position tuple {bof, X} | {cur, X} | {eof, X} into
%% {Offset, OriginCode} for the driver.
%% Returns badarg upon failure.

lseek_position(Pos)
  when is_integer(Pos) ->
    lseek_position({bof, Pos});
lseek_position(bof) ->
    lseek_position({bof, 0});
lseek_position(cur) ->
    lseek_position({cur, 0});
lseek_position(eof) ->
    lseek_position({eof, 0});
lseek_position({bof, Offset})
  when is_integer(Offset) ->
    {Offset, ?EFILE_SEEK_SET};
lseek_position({cur, Offset})
  when is_integer(Offset) ->
    {Offset, ?EFILE_SEEK_CUR};
lseek_position({eof, Offset})
  when is_integer(Offset) ->
    {Offset, ?EFILE_SEEK_END};
lseek_position(_) ->
    badarg.



%% Translates the response from the driver into 
%% {ok, Result} or {error, Reason}.

translate_response(?FILE_RESP_OK, []) ->
    ok;
translate_response(?FILE_RESP_ERROR, List) when is_list(List) ->
    {error, list_to_atom(List)};
translate_response(?FILE_RESP_NUMBER, List) ->
    {N, []} = get_uint64(List),
    {ok, N};
translate_response(?FILE_RESP_DATA, List) ->
    {_N, _Data} = ND = get_uint64(List),
    {ok, ND};
translate_response(?FILE_RESP_INFO, List) when is_list(List) ->
    {ok, transform_info_ints(get_uint32s(List))};
translate_response(?FILE_RESP_NUMERR, L0) ->
    {N, L1} = get_uint64(L0),
    {error, {N, list_to_atom(L1)}};
translate_response(?FILE_RESP_LDATA, List) ->
    {ok, transform_ldata(List)};
translate_response(?FILE_RESP_N2DATA, 
		   <<Offset:64, 0:64, Size:64>>) ->
    {ok, {Size, Offset, eof}};
translate_response(?FILE_RESP_N2DATA, 
		   [<<Offset:64, 0:64, Size:64>> | <<>>]) ->
    {ok, {Size, Offset, eof}};
translate_response(?FILE_RESP_N2DATA = X, 
		   [<<_:64, 0:64, _:64>> | _] = Data) ->
    {error, {bad_response_from_port, [X | Data]}};
translate_response(?FILE_RESP_N2DATA = X, 
		   [<<_:64, _:64, _:64>> | <<>>] = Data) ->
    {error, {bad_response_from_port, [X | Data]}};
translate_response(?FILE_RESP_N2DATA, 
		   [<<Offset:64, _ReadSize:64, Size:64>> | D]) ->
    {ok, {Size, Offset, D}};
translate_response(?FILE_RESP_N2DATA = X, L0) when is_list(L0) ->
    {Offset, L1}    = get_uint64(L0),
    {ReadSize, L2}  = get_uint64(L1),
    {Size, L3}      = get_uint64(L2),
    case {ReadSize, L3} of
	{0, []} ->
	    {ok, {Size, Offset, eof}};
	{0, _} ->
	    {error, {bad_response_from_port, [X | L0]}};
	{_, []} ->
	    {error, {bad_response_from_port, [X | L0]}};
	_ ->
	    {ok, {Size, Offset, L3}}
    end;
translate_response(?FILE_RESP_EOF, []) ->
    eof;
translate_response(?FILE_RESP_FNAME, []) ->
    ok;
translate_response(?FILE_RESP_FNAME, Data) when is_binary(Data) ->
    {ok, prim_file:internal_native2name(Data)};
translate_response(?FILE_RESP_FNAME, Data) ->
    {ok, Data};
translate_response(?FILE_RESP_LFNAME, []) ->
    ok;
translate_response(?FILE_RESP_LFNAME, Data) when is_binary(Data) ->
    {append, transform_lfname(Data)};
translate_response(?FILE_RESP_LFNAME, Data) ->
    {append, transform_lfname(Data)};
translate_response(?FILE_RESP_ALL_DATA, Data) ->
    {ok, Data};
translate_response(X, Data) ->
    {error, {bad_response_from_port, [X | Data]}}.

transform_info_ints(Ints) ->
    [HighSize, LowSize, Type|Tail0] = Ints,
    Size = HighSize * 16#100000000 + LowSize,
    [Ay, Am, Ad, Ah, Ami, As|Tail1]  = Tail0,
    [My, Mm, Md, Mh, Mmi, Ms|Tail2] = Tail1,
    [Cy, Cm, Cd, Ch, Cmi, Cs|Tail3] = Tail2,
    [Mode, Links, Major, Minor, Inode, Uid, Gid, Access] = Tail3,
    #file_info {
		size = Size,
		type = file_type(Type),
		access = file_access(Access),
		atime = {{Ay, Am, Ad}, {Ah, Ami, As}},
		mtime = {{My, Mm, Md}, {Mh, Mmi, Ms}},
		ctime = {{Cy, Cm, Cd}, {Ch, Cmi, Cs}},
		mode = Mode,
		links = Links,
		major_device = Major,
		minor_device = Minor,
		inode = Inode,
		uid = Uid,
		gid = Gid}.
    
file_type(1) -> device;
file_type(2) -> directory;
file_type(3) -> regular;
file_type(4) -> symlink;
file_type(_) -> other.

file_access(0) -> none;   
file_access(1) -> write;
file_access(2) -> read;
file_access(3) -> read_write.

int_to_bytes(Int) when is_integer(Int) ->
    <<Int:32>>;
int_to_bytes(undefined) ->
    <<-1:32>>.

date_to_bytes(undefined) ->
    <<-1:32, -1:32, -1:32, -1:32, -1:32, -1:32>>;
date_to_bytes({{Y, Mon, D}, {H, Min, S}}) ->
    <<Y:32, Mon:32, D:32, H:32, Min:32, S:32>>.

%% uint64([[X1, X2, X3, X4] = Y1 | [X5, X6, X7, X8] = Y2]) ->
%%     (uint32(Y1) bsl 32) bor uint32(Y2).

%% uint64(X1, X2, X3, X4, X5, X6, X7, X8) ->
%%     (uint32(X1, X2, X3, X4) bsl 32) bor uint32(X5, X6, X7, X8).

%% uint32([X1,X2,X3,X4]) ->
%%     (X1 bsl 24) bor (X2 bsl 16) bor (X3 bsl 8) bor X4.

uint32(X1,X2,X3,X4) ->
    (X1 bsl 24) bor (X2 bsl 16) bor (X3 bsl 8) bor X4.

get_uint64(L0) ->
    {X1, L1} = get_uint32(L0),
    {X2, L2} = get_uint32(L1),
    {(X1 bsl 32) bor X2, L2}.

get_uint32([X1,X2,X3,X4|List]) ->
    {(((((X1 bsl 8) bor X2) bsl 8) bor X3) bsl 8) bor X4, List}.

get_uint32s([X1,X2,X3,X4|Tail]) ->
    [uint32(X1,X2,X3,X4) | get_uint32s(Tail)];
get_uint32s([]) -> [].



%% Binary mode
transform_ldata(<<0:32, 0:32>>) ->
    [];
transform_ldata([<<0:32, N:32, Sizes/binary>> | Datas]) ->
    transform_ldata(N, Sizes, Datas, []);
%% List mode
transform_ldata([_,_,_,_,_,_,_,_|_] = L0) ->
    {0, L1} = get_uint32(L0),
    {N, L2} = get_uint32(L1),
    transform_ldata(N, L2, []).

%% List mode
transform_ldata(0, List, Sizes) ->
    transform_ldata(0, List, reverse(Sizes), []);
transform_ldata(N, L0, Sizes) ->
    {Size, L1} = get_uint64(L0),
    transform_ldata(N-1, L1, [Size | Sizes]).

%% Binary mode
transform_ldata(1, <<0:64>>, <<>>, R) ->
    reverse(R, [eof]);
transform_ldata(1, <<Size:64>>, Data, R) 
  when byte_size(Data) =:= Size ->
    reverse(R, [Data]);
transform_ldata(N, <<0:64, Sizes/binary>>, [<<>> | Datas], R) ->
    transform_ldata(N-1, Sizes, Datas, [eof | R]);
transform_ldata(N, <<Size:64, Sizes/binary>>, [Data | Datas], R) 
  when byte_size(Data) =:= Size ->
    transform_ldata(N-1, Sizes, Datas, [Data | R]);
%% List mode
transform_ldata(0, [], [], R) ->
    reverse(R);
transform_ldata(0, List, [0 | Sizes], R) ->
    transform_ldata(0, List, Sizes, [eof | R]);
transform_ldata(0, List, [Size | Sizes], R) ->
    {Front, Rear} = lists_split(List, Size),
    transform_ldata(0, Rear, Sizes, [Front | R]).

transform_lfname(<<>>) -> [];
transform_lfname(<<L:16, Name:L/binary, Names/binary>>) -> 
    [ prim_file:internal_native2name(Name) | transform_lfname(Names)];
transform_lfname([]) -> [];
transform_lfname([L1,L2|Names]) ->
    L = (L1 bsl 8) bor L2,
    {Name, Rest} = lists_split(Names, L),
    [Name | transform_lfname(Rest)].


lists_split(List, 0) when is_list(List) ->
    {[], List};
lists_split(List, N) when is_list(List), is_integer(N), N < 0 ->
    erlang:error(badarg, [List, N]);
lists_split(List, N) when is_list(List), is_integer(N) ->
    case lists_split(List, N, []) of
	premature_end_of_list ->
	    erlang:error(badarg, [List, N]);
	Result ->
	    Result
    end.

lists_split(List, 0, Rev) ->
    {reverse(Rev), List};
lists_split([], _, _) ->
    premature_end_of_list;
lists_split([Hd | Tl], N, Rev) ->
    lists_split(Tl, N-1, [Hd | Rev]).

%% We KNOW that lists:reverse/2 is a BIF.

reverse(X) -> lists:reverse(X, []).
reverse(L, T) -> lists:reverse(L, T).

% Will add zero termination too
% The 'EXIT' tuple from a bad argument will eventually generate an error
% in list_to_binary, which is caught and generates the {error,badarg} return
pathname(File) ->
    (catch prim_file:internal_name2native(File)).

%% TODO: Duplicate code!
get_dtrace_utag() ->
    case get(dtrace_utag) of
        X when is_list(X) ->
            X;
        _ ->
            ""
    end.

%% TODO: Measure if it's worth checking (re:run()?) for NUL byte first?
enc_utag([0|Cs]) ->
    enc_utag(Cs);
enc_utag([C|Cs]) ->
    [C|enc_utag(Cs)];
enc_utag([]) ->
    [0].
