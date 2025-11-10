<!--
SPDX-FileCopyrightText: Alex Turbov <zaufi@pm.me>
SPDX-License-Identifier: CC0-1.0
-->

# What is This

This is my bare minimum repo used as a template.

## TODO Check List for the new repository

- [x] Add the minimal must-have configuration files.

- [ ] Set the `master` (or `main`) branch name in the `.github/workflows/pre-commit-check.yaml`.

- [ ] Add your code.

- [ ] Provide description and introductory section to the `README.md` file.

- [ ] Read the [manual] and edit the `.github/CODEOWNERS` file.

- [ ] Use the `.gitignore` [properly] -- do not add your IDE-specific files!

- [ ] If not yet installed, set the `.github/commit-message.template` as commit message
      template. Copy it to some place in your `$HOME` directory (recommended is `~/.config/git/templates/`)
      and execute the command:

      git config --global commit.template <path-to-copied-template>

  Unlike the name, `--global` means _user_ ;-). To install system-wide use `--system`.

- [ ] Remove this section ;-)

[manual]: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
[properly]: https://www.pluralsight.com/guides/how-to-use-gitignore-file

## How to Contribute

1. Fork a `feature/*` or `bug/*` branch from the `master`.

2. Avoid doing too much in a single branch. Things unrelated to the current
   task must be in separate branches and pull requests.

3. For every commit, provide a comment describing _what has been done and why_.

4. Test your work locally before opening a pull request.

5. Open a pull request. Provide a detailed description giving hints to reviewers on:
   - what they are going to review;
   - what was before and why these changes are needed;
   - maybe a description of some subtle implementation details;
   - anything else that can help reviewers understand your idea and
     **spend less time on review**.

6. **Rebase** to `master` performed by the **PR assigner** when review passed.

7. Your feature/fix will appear in the next release.
