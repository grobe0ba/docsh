-module(install_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(eq(Expected, Actual), ?assertEqual(Expected, Actual)).

-define(b2l(B), binary_to_list(B)).
-define(il2b(IL), iolist_to_binary(IL)).

all() ->
    [docker_linux].

init_per_suite(Config) ->
    [ check(P, Config) || P <- prerequisites() ],
    Config.

prerequisites() ->
    [
     { "docker in $PATH", fun (_Config) -> {_, _, <<"Docker", _/bytes>>} = sh("docker -v") end },
     { "git in $PATH", fun (_) -> {_, _, <<"usage: git", _/bytes>>} = sh("git --help") end }
    ].

end_per_suite(_Config) ->
    ok.

%%
%% Config
%%

docsh_repo() ->
    "https://github.com/erszcz/docsh".

%%
%% Tests
%%

docker_linux(_) ->
    %% debug shell commands?
    %put(sh_log, true),
    Name = container_name("docsh-linux-"),
    Args = [which("docker"), "run", "-t", "--rm", "--name", Name, "erlang:19-slim", "bash"],
    start_container(Name, Args),
    GitRef = current_git_commit(),
    try
        sh(within_container(Name, fetch(archive_url(GitRef), archive_file(GitRef)))),
        sh(within_container(Name, extract(archive_file(GitRef)))),
        sh(within_container(Name, install(repo_dir(GitRef)))),
        sh(within_container(Name, file_exists("$HOME/.erlang"))),
        sh(within_container(Name, file_exists("$HOME/.erlang.d/user_default.erl"))),
        sh(within_container(Name, file_exists("$HOME/.erlang.d/user_default.beam"))),
        sh(within_container(Name, docsh_works()))
    after
        sh("docker stop " ++ Name)
    end.

%%
%% Helpers
%%

check({Name, P}, Config) ->
    try
        P(Config),
        ok
    catch _:Reason ->
        ct:fail("~ts failed: ~p", [Name, Reason])
    end.

container_name(Prefix) ->
    RawRandomBytes = crypto:strong_rand_bytes(9),
    Base64 = base64:encode(RawRandomBytes),
    DockerCompliant = re:replace(Base64, <<"[^a-zA-Z0-9_.-]">>, <<"x">>, [global]),
    ?b2l(?il2b([Prefix, DockerCompliant])).

which(Command) ->
    {done, 0, BPath} = sh("which " ++ Command),
    ?b2l(BPath).

sh(Command) when is_binary(Command) -> sh([Command]);
sh(Command) ->
    case erlsh:oneliner(?b2l(?il2b(Command))) of
        {done, 0 = Code, Result} = R ->
            get(sh_log) == true andalso sh_log(Command, Code, Result),
            R;
        {done, Code, Result} = R ->
            sh_log(Command, Code, Result),
            ct:fail(R)
    end.

sh_log(Command, Code, Result) ->
    ct:pal("command : ~ts\n"
           "code    : ~p\n"
           "result  : ~ts",
           [Command, Code, Result]).

start_container(Name, Args) ->
    Fdlink = erlsh:fdlink_executable(),
    _ContainerPort = erlang:open_port({spawn_executable, Fdlink}, [stream, exit_status, {args, Args}]),
    wait_for(fun () -> is_container_running(Name) end).

wait_for(Predicate) ->
    wait_for(Predicate, 5000).

wait_for(_Predicate, Timeout) when Timeout < 0 ->
    error(timeout);
wait_for( Predicate, Timeout) ->
    case Predicate() of
        true -> ok;
        false ->
            timer:sleep(100),
            wait_for(Predicate, Timeout - 100)
    end.

is_container_running(Name) ->
    try
        sh(["docker ps | grep ", Name, " | grep Up"]),
        true
    catch _:_ -> false end.

current_git_commit() ->
    {_, _, R} = sh("git rev-parse HEAD"),
    R.

% Url = https://github.com/erszcz/docsh/archive/456d80379fcf81a823a63db13aa2f66f28abd79e.tar.gz
% TargetFile = /tmp/z.tar.gz
fetch(Url, Target) ->
    QUrl = quote(Url),
    QTarget = quote(Target),
    ["erl -noinput -noshell -s ssl -s inets "
     "-eval '{ok, {_, _, D}} = httpc:request(", QUrl, "), file:write_file(", QTarget, ", D).' "
     "-s erlang halt"].

quote(Text) ->
    ["\"", Text, "\""].

within_container(Name, Command) ->
    ["docker exec ", Name, " ", Command].

archive_url(GitReference) ->
    [docsh_repo(), "/archive/", GitReference, ".tar.gz"].

archive_file(GitReference) ->
    [GitReference, ".tar.gz"].

extract(Archive) ->
    ["tar xf ", Archive].

repo_dir(GitReference) ->
    ["docsh-", GitReference].

install(RepoDir) ->
    ["cd ", RepoDir, "; yes | ./install.sh"].

file_exists(File) ->
    ["file -E ", File].

docsh_works() ->
    ["erl -noinput -noshell -eval 'erlang:display(docsh:module_info(module)).' -s erlang halt"].
