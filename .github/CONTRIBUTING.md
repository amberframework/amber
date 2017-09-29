# Contributing to Amber

First thank you for taking the time to contribute and making our community great!

Amber is an open source project and we love to receive contributions from our community — you! The following is a set of guidelines for contributing to Amber, which are hosted in the Amber Framework on GitHub.

Following these guidelines helps to communicate that you respect the time of the developers managing and developing this open source project. In return, they should reciprocate that respect in addressing your issue, assessing changes, and helping you finalize your pull requests. These are just guidelines, not rules. Use your best judgment, and feel free to propose changes to this document in a pull request.

### Table of contents

[What should I know before I get started?](#what-should-i-know-before-i-get-started)

  * [Code of Conduct](./CODE_OF_CONDUCT.md)
  * [Ground Rules](#ground-rules)

[How Can I Contribute?](#how-can-i-contribute)

  * [Reporting Bugs](#reporting-bugs)
  * [Suggesting Enhancements](#suggesting-enhancements)
  * [Your First Contribution](#your-first-contribution)
  * [Pull Requests](#pull-requests)

[Style Guides](#style-guides)

  * [Coding Style Guides](#coding-style-guidelines)
  * [Documenting code](#documenting-code)
  * [Spec Style Guides](#spec-style-guides)

## What should I know before I get started?
### Ground Rules

Be a law abiding contributor!

This project adheres to the Contributor Covenant [CODE OF CONDUCT](https://github.com/amberframework/amber/blob/master/.github/CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to [gitter channel](https://gitter.im/amberframework/amber)

## How Can I Contribute

### How to report a bug

This section guides you through submitting a bug report for Amber. Following these guidelines helps maintainers and the community understand your report, reproduce the behavior, and find related reports.

**Before Submitting A Bug Report**

Before creating bug reports, please check this list as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible. Fill out the required template, the information it asks for helps us resolve issues faster.

**How Do I Submit A (Good) Bug Report?**

Bugs are tracked as [GitHub issues](https://github.com/amberframework/amber/issues). After you've determined the cause of the bug, create an issue and provide the following information by filling in the template.

**A good bug report**

* Contains the information needed to reproduce and fix problems
* Is an efficient form of communication for both bug reporter and bug receiver
* Is resolved as fast as possible
* Is sent to the person in charge
* Establishes a common ground of collaboration

Explain the problem and include additional details to help maintainers reproduce the problem:

* Use a clear and descriptive title for the issue to identify the problem.
* Describe the exact steps which reproduce the problem in as many details as possible. For example, start by explaining how you started Amber, e.g. which command exactly you used in the terminal, or how you started A,ber otherwise. When listing steps, don't just say what you did, but explain how you did it. For example, if you moved the cursor to the end of a line, explain if you used the mouse, or a keyboard shortcut or an Amber command, and if so which one?
* Provide specific examples to demonstrate the steps. Include links to files or GitHub projects, or copy/pasteable snippets, which you use in those examples. If you're providing snippets in the issue, use Markdown code blocks.
* Describe the behavior you observed after following the steps and point out what exactly is the problem with that behavior.
* Explain which behavior you expected to see instead and why.
* Include screenshots and animated GIFs which show you following the described steps and clearly demonstrate the problem. If you use the keyboard while following the steps, record the GIF with the Keybinding Resolver shown. You can use this tool to record GIFs on macOS and Windows, and this tool or this tool on Linux.
* If the problem is related to performance, include a CPU profile capture and a screenshot with your report.
* If the problem wasn't triggered by a specific action, describe what you were doing before the problem happened and share more information using the guidelines below.

### How to suggest a feature or enhancement

This section guides you through submitting an enhancement suggestion for Amber, including completely new features and minor improvements to existing functionality. Following these guidelines helps maintainers and the community understand your suggestion and find related suggestions.

Before creating enhancement suggestions, please check this list as you might find out that you don't need to create one. When you are creating an enhancement suggestion, please include as many details as possible. Fill in the template, including the steps that you imagine you would take if the feature you're requesting existed.

**Before Submitting An Enhancement Suggestion**
 * Check if there's already a shard which provides that enhancement.
 * Perform a cursory search to see if the enhancement has already been suggested. If it has, add a comment to the existing issue instead of opening a new one.

**How Do I Submit A (Good) Enhancement Suggestion?**

Enhancement suggestions are tracked as GitHub issues. After you've determined which repository your enhancement suggestion is related to, create an issue on that repository and provide the following information:

* Use a clear and descriptive title for the issue to identify the suggestion.
* Provide a step-by-step description of the suggested enhancement in as many details as possible.
* Provide specific examples to demonstrate the steps. Include copy/pasteable snippets which you use in those examples, as Markdown code blocks.
* Describe the current behavior and explain which behavior you expected to see instead and why.
* Include screenshots and animated GIFs which help you demonstrate the steps or point out the part of Amber which the suggestion is related to. You can use this tool to record GIFs on macOS and Windows, and this tool or this tool on Linux.
* Explain why this enhancement would be useful to most Amber users and isn't something that can or should be implemented as a community package.
* List some other text editors or applications where this enhancement exists.
* Specify which version of Amber you're using. You can get the exact version by running Amber -v in your terminal, or by starting Amber and running the Application: About command from the Command Palette.
* Specify the name and version of the OS you're using.

### Your First Contribution

Unsure where to begin contributing to Amber? You can start by looking through these beginner and help-wanted issues:

Beginner issues - issues which should only require a few lines of code, and a test or two.
Help wanted issues - issues which should be a bit more involved than beginner issues.
Both issue lists are sorted by total number of comments. While not perfect, number of comments is a reasonable proxy for impact a given change will have.

### Pull Requests

* Fill in the required template
* Document new code based on the [Documenting Code](https://crystal-lang.org/docs/conventions/documenting_code.html)
* Include thoughtfully-worded, well-structured
* End files with a newline.
* Format your code with `crystal tool format`
* Specs Styleguide

## Coding Style Guides

* [Style Guide](https://crystal-lang.org/docs/conventions/coding_style.html)

## Documenting code

* [Documenting Code](https://crystal-lang.org/docs/conventions/documenting_code.html)

## Spec Guides

* Include thoughtfully-worded, well-structured Crystal specs in the `./spec` folder.
* Treat `describe` as a noun or situation.
* Teat `it` as a statement about state or how an operation changes state.
