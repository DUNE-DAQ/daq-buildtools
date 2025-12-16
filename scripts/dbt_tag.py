import os, sys
import re
import argparse
import click
from git import Repo
from git.exc import GitCommandError
from pathlib import Path
from textwrap import dedent
from dataclasses import dataclass

DBT_ROOT=os.environ["DBT_ROOT"]
exec(open(f'{DBT_ROOT}/scripts/dbt_setup_constants.py').read())
sys.path.append(f'{DBT_ROOT}/scripts')

from dbt_setup_tools import run_command

@dataclass(order=True)
class RepoTag:
    tag: str

    @property
    def major(self):
        return int(self.tag.split('.')[0].replace('v', ''))

    @property
    def minor(self):
        return int(self.tag.split('.')[1])

    @property
    def patch(self):
        return int(self.tag.split('.')[2])

    def __post_init__(self):
        parts = self.tag[1:].split('.')
        if len(parts) != 3 or not all(p.isdigit() for p in parts) or not self.tag.startswith('v'):
            raise click.BadParameter(f"Invalid tag format: '{self.tag}'. Format should be 'vX.Y.Z'.")

class DAQRepo:
    def __init__(self, repo_tag):
        self.repo_tag = repo_tag
        self.gitrepo = Repo('.', search_parent_directories=True)
        self.latest_tag = self.get_latest_tag()
        self.top = Path(self.gitrepo.git.rev_parse("--show-toplevel"))
        self.name = os.path.basename(self.gitrepo.working_tree_dir)
        self.cmakelists_path = Path(self.top / "CMakeLists.txt")
        self.pyproject_path  = Path(self.top / "pyproject.toml")
        self.cmakelists_tag = None
        self.pyproject_tag  = None

        if self.repo_tag.tag < self.latest_tag.tag:
            raise click.UsageError(f"The requested tag {self.repo_tag.tag} is older than the most recent tag: {self.latest_tag.tag}.")
        if self.repo_tag.tag == self.latest_tag.tag:
            raise click.UsageError(
                f"{self.repo_tag.tag} already exists.\n\n"
                f"If you need to revert your current tag, use dbt-tag delete <tag>"
            )

    def get_latest_tag(self):
        latest_tag = run_command("git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1", capture=True)
        return RepoTag(latest_tag)

    def update_cmakelists_tag(self, dry_run=False):
        if not self.cmakelists_path.exists():
            return
        new_version = self.repo_tag.tag.lstrip('v')
        text = self.cmakelists_path.read_text()
        pattern = r"(project\s*\(\s*[^ )]+\s+VERSION\s+)([\d\.]+)"
        repl = r"\g<1>" + new_version

        if dry_run:
            match = re.search(pattern, text)
            if match:
                old_line = match.group(0)
                new_line = re.sub(pattern, repl, old_line)
                if old_line == new_line:
                    click.echo("\nThis action would make no change to the current CMakeLists.txt.")
                    return
                click.echo("Changes to CMakeLists.txt:")
                click.secho(f"{old_line})", fg='yellow')
                click.secho(f"{new_line})", fg='bright_cyan')
        else:
            new_text = re.sub(pattern, repl, text)
            self.cmakelists_path.write_text(new_text)
            click.secho(f"Updated version to {new_version} in {self.cmakelists_path}", fg="blue")

    def update_pyproject_tag(self, dry_run=False):
        if not self.pyproject_path.exists():
            return
        new_version = self.repo_tag.tag.lstrip('v')
        text = self.pyproject_path.read_text()
        pattern = r'(version\s*=\s*")(\d+\.\d+\.\d+)(")'
        repl = r"\g<1>" + new_version + r"\g<3>"

        if dry_run:
            match = re.search(pattern, text)
            if match:
                old_line = match.group(0)
                new_line = re.sub(pattern, repl, old_line)
                if old_line == new_line:
                    click.echo("\nThis action would make no change to the current pyproject.toml.")
                    return
                click.echo("\nChanges to pyproject.toml:")
                click.secho(f"{old_line}", fg='yellow')
                click.secho(f"{new_line}", fg='bright_cyan')
        else:
            new_text = re.sub(pattern, repl, text)
            self.pyproject_path.write_text(new_text)
            click.secho(f"\nUpdated version to {new_version} in {self.pyproject_path}", fg="blue")

    def create_and_checkout_branch(self, branch, overwrite, dry_run=False):
        if overwrite:
            if branch in self.gitrepo.refs:
                try:
                    self.gitrepo.git.branch("-D", f"{branch}")
                except GitCommandError as e:
                    raise RuntimeError(
                        f"Cannot delete branch {branch}. Make sure it's not already checked out."
                    ) from e
            else:
                click.echo("Nope")
        if dry_run:
            click.secho(f"\nThis action would create and checkout a branch called {branch} with the changes listed below.")
            return
        self.gitrepo.git.switch('-c', branch)
        click.echo(f"\nSwitched to new branch {branch}")

    def commit_changes(self, dry_run=False):
        if dry_run:
            diff_text = self.gitrepo.git.diff("HEAD~1", color="always")
            click.echo("Changes to be committed:")
            click.echo(diff_text)
            return
        if self.cmakelists_path.exists():
            self.gitrepo.index.add(["CMakeLists.txt"])
            click.echo("CMakeLists added")
        if self.pyproject_path.exists():
            self.gitrepo.index.add(["pyproject.toml"])
            click.echo("pyproject added")
        self.gitrepo.index.commit("[DBT-TAG]: Bump version numbers")
        click.echo("Committed")
        diff_text = self.gitrepo.git.diff("HEAD~1", color="always")
        click.echo(diff_text)


@click.group()
@click.option("--dry-run", is_flag=True, help="Show actions without running them.")
@click.pass_context
def cli(ctx, dry_run):
    """Manage DUNE DAQ repo tags."""
    ctx.ensure_object(dict)
    ctx.obj["dry_run"] = dry_run

@cli.command()
@click.argument("tag")
@click.option("--branch", required=True, help="Branch from which the tag will be committed and pushed.")
@click.option("--overwrite", is_flag=True, help="Whether to overwrite the tagged branch if it already exists.")
@click.pass_context
def create(ctx, tag, branch, overwrite):
    repo_tag = RepoTag(tag)
    daq_repo = DAQRepo(repo_tag)
    daq_repo.create_and_checkout_branch(branch, overwrite, ctx.obj["dry_run"])
    daq_repo.update_cmakelists_tag(ctx.obj["dry_run"])
    daq_repo.update_pyproject_tag(ctx.obj["dry_run"])
    daq_repo.commit_changes(ctx.obj["dry_run"])

@cli.command()
@click.argument("tag")
@click.pass_context
def push(ctx, tag):
    repo_tag = RepoTag(tag)
    click.echo(f"Push tag {tag}")

@cli.command()
@click.argument("tag")
@click.pass_context
def delete(ctx, tag):
    repo_tag = RepoTag(tag)
    daq_repo = DAQRepo(repo_tag)
    latest_tag = daq_repo.get_latest_tag()
    daq_repo.update_cmakelists_tag(latest_tag.tag, ctx.obj["dry_run"])
    daq_repo.update_pyproject_tag(latest_tag.tag, ctx.obj["dry_run"])

if __name__ == "__main__":
    cli()