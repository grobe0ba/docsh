-module(rebar3_prv_docsh_SUITE).
-compile([export_all]).

-import(docsh_helpers, [check_precondition/2,
                        sh/1]).

init_per_suite(Config) ->
    [ check_precondition(P, Config) || P <- preconditions() ],
    Config.

preconditions() ->
    [
     { "git in $PATH", fun (_) -> {_, _, <<"usage: git", _/bytes>>} = sh("git --help") end }
    ].

end_per_suite(_Config) ->
    ok.

all() ->
    [rebar3_prv_docsh_compiles_in_the_docs_chunk].

%%
%% Config
%%

recon_repo() ->
    "https://github.com/erszcz/recon".

%%
%% Tests
%%

rebar3_prv_docsh_compiles_in_the_docs_chunk(_) ->
    put(sh_log, true),
    %% given
    AppName = "recon",
    sh(clone(recon_repo())),
    %% when
    {ok, ProjectDir} = compile(AppName),
    %% then all modules have the "Docs" chunk
    {ok, Modules} = app_modules(AppName, ProjectDir),
    ModuleDocs = [ begin
                       %% Not using docsh here so we're 100% sure it doesn't make docs_v1 on demand.
                       BeamFile = code:which(M),
                       {ok, {_Mod, [{"Docs", BDocs}]}} = beam_lib:chunks(BeamFile, ["Docs"]),
                       {ok, erlang:binary_to_term(BDocs)}
                   end || M <- Modules ],
    ct:pal("~s module docs:\n~p", [AppName, ModuleDocs]),
    [ok, ok, ok, ok] = [ element(1, MD) || MD <- ModuleDocs ],
    ok.

%%
%% Helpers
%%

quote(Text) ->
    ["\"", Text, "\""].

clone(Repo) ->
    ["git clone ", Repo].

compile(Project) ->
    {ok, Dir} = file:get_cwd(),
    ProjectDir = filename:join([Dir, Project]),
    try
        ok = file:set_cwd(ProjectDir),
        rebar_agent:start_link(rebar_state:new()),
        r3:compile(),
        {ok, ProjectDir}
    after
        ok = file:set_cwd(Dir)
    end.

app_modules(AppName, ProjectDir) ->
    AppFile = filename:join([ProjectDir, "_build", "default", "lib", AppName, "ebin", AppName ++ ".app"]),
    {ok, AppSpec} = file:consult(AppFile),
    [{application, recon, AppProps}] = AppSpec,
    {modules, Modules} = lists:keyfind(modules, 1, AppProps),
    {ok, Modules}.
