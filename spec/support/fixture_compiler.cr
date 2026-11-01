# Names the compiler for specs that build a standalone program from
# `spec/fixtures/` and run it in a child process.
#
# The rule: `CRYSTAL` when it is set, otherwise `crystal-alpha` from `PATH`.
# Every CI job sets `CRYSTAL=crystal`, because in each of them the compiler on
# `PATH` named `crystal` is the one that runs the suite (Crystal 1.22.1 from
# the verified tarball, crystal-alpha built from its pinned commit, or the
# digest-pinned CircleCI image). Locally the house compiler is crystal-alpha.
# There is deliberately no fallback to whatever `crystal` happens to be on
# `PATH`: a fixture built by a different compiler than the suite would test
# that compiler instead, so a missing compiler raises and says how to fix it.
module FixtureCompiler
  class NotFound < Exception
  end

  def self.executable : String
    if compiler = ENV["CRYSTAL"]?.presence
      return compiler
    end

    if crystal_alpha = Process.find_executable("crystal-alpha")
      return crystal_alpha
    end

    raise NotFound.new(
      "No compiler for spec fixture programs: set CRYSTAL to the compiler " \
      "that runs this suite (CI sets CRYSTAL=crystal), or install crystal-alpha"
    )
  end
end
