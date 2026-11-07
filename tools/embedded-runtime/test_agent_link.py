"""Compile and test the native peer mailbox and shipped Godot client on the JVM."""
import argparse
import concurrent.futures
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[2]
MAVEN = 'https://repo.maven.apache.org/maven2/'
NS = {'m': 'http://maven.apache.org/POM/4.0.0'}


def fetch(cache, coordinate):
    group, artifact, version = coordinate
    assert all(re.fullmatch(r'[a-zA-Z0-9_.-]+', part) for part in coordinate)
    relative = f'{group.replace(".", "/")}/{artifact}/{version}/{artifact}-{version}.jar'
    target = cache / relative.rsplit('/', 1)[-1]
    if not target.exists():
        temporary = target.with_suffix('.part')
        with urllib.request.urlopen(MAVEN + relative, timeout=60) as source, temporary.open('wb') as output:
            while chunk := source.read(1024 * 1024):
                output.write(chunk)
        temporary.replace(target)
    try:
        with urllib.request.urlopen(MAVEN + relative + '.sha256', timeout=20) as response:
            expected = response.read().decode().strip().split()[0]
        algorithm = 'sha256'
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        with urllib.request.urlopen(MAVEN + relative + '.sha1', timeout=20) as response:
            expected = response.read().decode().strip().split()[0]
        algorithm = 'sha1'
    with target.open('rb') as stream:
        assert hashlib.file_digest(stream, algorithm).hexdigest() == expected, target.name


def compiler(cache):
    cache.mkdir(parents=True, exist_ok=True)
    config = (REPO / 'platform/android/java/app/config.gradle').read_text()
    version = re.search(r"kotlinVersion\s*:\s*'([^']+)'", config)[1]
    relative = f'org/jetbrains/kotlin/kotlin-compiler-embeddable/{version}/kotlin-compiler-embeddable-{version}.pom'
    with urllib.request.urlopen(MAVEN + relative, timeout=30) as response:
        pom = ET.fromstring(response.read())
    coordinates = [('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', version),
                   ('org.json', 'json', '20240303'), ('org.jetbrains', 'annotations', '13.0')]
    for dependency in pom.findall('m:dependencies/m:dependency', NS):
        coordinates.append(tuple(dependency.findtext('m:' + key, namespaces=NS)
                                 for key in ['groupId', 'artifactId', 'version']))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda item: fetch(cache, item), coordinates))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--cache', type=Path, default=REPO / '.ai-qa/agent-link-kotlin')
    parser.add_argument('--compiler-directory', type=Path, help='Use already prepared compiler/dependency JARs')
    args = parser.parse_args()
    cache = args.compiler_directory or args.cache
    if args.compiler_directory is None:
        compiler(cache)
    jars = os.pathsep.join(str(path.resolve()) for path in cache.glob('*.jar'))
    assert jars, 'Compiler JARs are unavailable'
    java = REPO / 'platform/android/java/editor/src/main/java/org/godotengine/editor'
    tests = REPO / 'tools/embedded-runtime/tests'
    with tempfile.TemporaryDirectory(prefix='godot-agent-link-tests-') as directory:
        command = ['java', '-Djansi.mode=strip', '-cp', jars, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                   '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', jars, '-d', directory]
        subprocess.run(command + [str(java / name) for name in ['AIZivaAgentLink.kt', 'AIZivaChat.kt', 'AIZivaProjectContext.kt']]
                       + [str(tests / name) for name in ['AgentLinkTest.kt', 'ZivaChatLinkTest.kt', 'ZivaProjectContextTest.kt']], check=True)
        classpath = directory + os.pathsep + jars
        client = REPO / 'platform/android/java/editor/src/main/assets/ai/agent-link-client.gd'
        subprocess.run(['java', '-cp', classpath, 'AgentLinkTestKt', str(client), args.godot], check=True)
        subprocess.run(['java', '-cp', classpath, 'ZivaProjectContextTestKt'], check=True)


if __name__ == '__main__':
    main()
