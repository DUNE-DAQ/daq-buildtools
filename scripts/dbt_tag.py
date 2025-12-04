import os, sys
import argparse
import click
from textwrap import dedent
from dataclasses import dataclass

DBT_ROOT=os.environ["DBT_ROOT"]
exec(open(f'{DBT_ROOT}/scripts/dbt_setup_constants.py').read())
sys.path.append(f'{DBT_ROOT}/scripts')

from dbt_setup_tools import error, run_command

@dataclass(order=True)
class RepoTag:
    tag: str
    is_pymodule: bool = False
    is_cpp_package: bool = False

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
        if not self.tag.startswith('v'):
            raise ValueError("Tag must start with 'v'")

        parts = self.tag[1:].split('.')
        if len(parts) != 3 or not all(p.isdigit() for p in parts):
            raise ValueError(f"Invalid tag format: '{self.tag}'. Format should be 'vX.Y.Z'.")

@click.group()
@click.option("--dry-run", is_flag=True, help="Show actions without running them.")
@click.pass_context
def cli(ctx, dry_run):
    """Manage DUNE DAQ repo tags."""
    ctx.ensure_object(dict)
    ctx.obj["dry_run"] = dry_run

@cli.command()
@click.argument("tag")
@click.pass_context
def create(ctx, tag):
    repo_tag = RepoTag(tag)
    latest_tag = RepoTag(run_command("git describe --tags $(git rev-list --tags --max-count=1)", capture=True))
    if repo_tag < latest_tag:
        print('oops')
    click.echo(f"Create tag {tag}")

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
    click.echo(f"Delete {tag}")

if __name__ == "__main__":
    cli()