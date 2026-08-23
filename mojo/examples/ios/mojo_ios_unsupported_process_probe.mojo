# This source must fail during iOS compilation with the explicit subprocess
# diagnostic from std.os.Process.run.

from std.collections import List
from std.os import Process


def main() raises:
    _ = Process.run("echo", List[String]())
