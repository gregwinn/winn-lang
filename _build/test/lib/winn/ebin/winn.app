{application,winn,
             [{description,"The Winn programming language compiler"},
              {vsn,"0.1.0"},
              {registered,[]},
              {applications,[kernel,stdlib,compiler]},
              {env,[]},
              {modules,[winn,winn_ast,winn_changeset,winn_cli,winn_codegen,
                        winn_core_emit,winn_lexer,winn_parser,winn_repo,
                        winn_runtime,winn_semantic,winn_transform]}]}.
