#!/usr/bin/env python3

import argparse
import logging
import hashlib
import requests
import shutil
import json
import sys
import os
from subprocess import PIPE, Popen
from requests.auth import HTTPBasicAuth

logging.basicConfig(level=logging.INFO,
                    stream=sys.stdout,
                    format='%(asctime)-15s %(levelname)s - %(message)s')

logger = logging.getLogger(__name__)

# ./promote.py conexus-rc-local gov.gsa.cnxs ${bamboo.module_name} ${bamboo.maven.version} --username "${bamboo.artifactory_admin_username}" --password "${bamboo.artifactory_admin_password}" --override

class Promote(object):

    def __init__(self, **kwargs):
        """
        Update instance variables with those passed in from the command line
        """
        if all(kwargs[k] for k in ('username', 'password')):
            kwargs['auth'] = True
        elif any(kwargs[k] for k in ('username', 'password')):
            raise AttributeError("Please provide both username and password when using basic auth")
        self.__dict__.update(kwargs)
        self.staging_directory = os.path.join(os.getcwd(), 'working')

    def _open_subprocess(self, arguments):
        """
        Execute a command from the cli
        """
        return Popen(arguments,
                     shell=False,
                     stdin=PIPE,
                     stdout=PIPE,
                     stderr=PIPE)

    def _run_command(self, arguments):
        """
        Wrapper around open_subprocess to execute a command
        """
        try:
            p = self._open_subprocess(arguments)
            stdout, stderr = p.communicate()
            retcode = p.returncode
            if stdout:
                logger.info(stdout.decode(errors='ignore'))
            if stderr:
                logger.error(stderr.decode(errors='ignore'))
            return stdout, stderr, retcode
        except OSError:
            raise RuntimeError('Failed to execute {0}'.format(' '.join(arguments)))

    def _hash_file(self, file):
        """
        Get the sha1 hash of a file
        """
        BLOCKSIZE = 65536
        hash = hashlib.sha1()

        if not os.path.isfile(file):
            logger.error('Unable to hash {0}'.format(file))
            return 0
        with open(file, 'rb') as hash_file:
            buf = hash_file.read(BLOCKSIZE)
            while len(buf) > 0:
                hash.update(buf)
                buf = hash_file.read(BLOCKSIZE)
            return hash.hexdigest()

    def _get_packaging(self, artifact):
        """
        Determine packaging for artifacts that need an explicit type
        """
        if artifact.endswith('.tar.gz'):
            return 'tar.gz'
        if artifact.endswith('.tar'):
            return 'tar'
        if artifact.endswith('.zip'):
            return 'zip'
        if artifact.endswith('.war'):
            return 'war'
        if artifact.endswith('.jar'):
            return 'jar'
        return None

    def _get_classifier(self, artifact):
        """
        Determine classifier for artifacts that need one
        """
        if artifact.endswith('-tests.jar'):
            return 'tests'
        return None

    def _get_pom_file(self, path, artifact):
        """
        Determine the pom file to use when uploading an artifact
        """
        pieces = artifact.split('.')
        minor, _ = pieces[-2:]
        pieces = pieces[:-2]
        if minor.endswith('-tests'):
            minor = minor.rstrip('-tests')
        pieces += [minor, 'pom']
        pom_file = os.path.join(path, '.'.join(pieces))
        return pom_file

    def _strip_version_suffixes(self, filename):
        """
        Remove version suffixes from a filename stem so related artifacts
        can be grouped together.
        """
        stem = filename

        if stem.endswith('.tar.gz'):
            stem = stem[:-7]
        else:
            stem = os.path.splitext(stem)[0]

        suffixes = [
            f'-{self.version}-RC-tests',
            f'-{self.version}-tests',
            f'-{self.version}-RC',
            f'-{self.version}',
        ]

        for suffix in suffixes:
            if stem.endswith(suffix):
                return stem[:-len(suffix)]

        return stem

    def _group_artifacts_to_publish(self):
        """
        Group staged artifacts by directory + logical artifact base name so that
        a main artifact, pom, and tests jar can be deployed in a single Maven command.
        """
        grouped = {}

        for root, dirs, files in os.walk(self.staging_directory):
            for file in files:
                key = (root, self._strip_version_suffixes(file))
                if key not in grouped:
                    grouped[key] = {
                        'root': root,
                        'base': key[1],
                        'pom': None,
                        'main': None,
                        'tests': None,
                        'others': []
                    }

                entry = grouped[key]

                if file.endswith('.pom'):
                    entry['pom'] = file
                elif file.endswith('-tests.jar'):
                    entry['tests'] = file
                elif file.endswith('.jar') or file.endswith('.war'):
                    entry['main'] = file
                else:
                    entry['others'].append(file)

        return list(grouped.values())

    def _build_group_maven_cmd(self, artifact_group):
        """
        Build a single Maven deploy-file command for one logical artifact group.
        """
        mvn = '/usr/bin/mvn'
        deploy = 'deploy:deploy-file'
        settings_xml = self.settings_xml or '/usr/share/maven/conf/settings-release.xml'
        url = f'-Durl={self.server}/artifactory/{self.release_repo}'
        repo_id = '-DrepositoryId=central'

        root = artifact_group['root']
        pom = artifact_group['pom']
        main = artifact_group['main']
        tests = artifact_group['tests']

        command = [mvn, deploy, url, repo_id, '-s', settings_xml]

        if pom and not main and not tests:
            pom_path = os.path.join(root, pom)
            command.extend([
                f'-Dfile={pom_path}',
                f'-DpomFile={pom_path}'
            ])

            if self.maven_args:
                for argument in self.maven_args:
                    command.append(f'-D{argument}')

            return command

        if not pom:
            raise RuntimeError(
                f"Missing pom file for artifact group '{artifact_group['base']}' in {root}"
            )

        pom_path = os.path.join(root, pom)

        if main:
            main_path = os.path.join(root, main)
            command.extend([
                f'-Dfile={main_path}',
                f'-DpomFile={pom_path}',
                '-DgeneratePom=false'
            ])
            packaging = self._get_packaging(main)
            if packaging:
                command.append(f'-Dpackaging={packaging}')
        else:
            raise RuntimeError(
                f"Missing main artifact for artifact group '{artifact_group['base']}' in {root}"
            )

        attached_files = []
        attached_classifiers = []
        attached_types = []

        if tests:
            attached_files.append(os.path.join(root, tests))
            attached_classifiers.append('tests')
            attached_types.append('jar')

        if attached_files:
            command.extend([
                f"-Dfiles={','.join(attached_files)}",
                f"-Dclassifiers={','.join(attached_classifiers)}",
                f"-Dtypes={','.join(attached_types)}"
            ])

        if self.maven_args:
            for argument in self.maven_args:
                command.append(f'-D{argument}')

        return command

    def _remove_local_artifacts(self, artifacts):
        """
        Delete staged local artifacts
        """
        if os.path.isdir(self.staging_directory):
            shutil.rmtree(self.staging_directory)

    def _publish_artifacts(self):
        """
        Publish artifacts to Artifactory as grouped Maven deploy operations.
        """
        success = []
        failed = []

        artifact_groups = self._group_artifacts_to_publish()

        for artifact_group in artifact_groups:
            try:
                command = self._build_group_maven_cmd(artifact_group)
                logger.info('Running Maven deploy command: %s', ' '.join(command))
                stdout, stderr, retcode = self._run_command(command)

                display_names = []
                if artifact_group.get('pom'):
                    display_names.append(artifact_group['pom'])
                if artifact_group.get('main'):
                    display_names.append(artifact_group['main'])
                if artifact_group.get('tests'):
                    display_names.append(artifact_group['tests'])

                if retcode == 0:
                    success.extend(display_names)
                else:
                    failed.extend(display_names)

            except Exception as exc:
                logger.exception(
                    "Failed while preparing/publishing artifact group '%s' from %s",
                    artifact_group.get('base'),
                    artifact_group.get('root')
                )

                display_names = []
                if artifact_group.get('pom'):
                    display_names.append(artifact_group['pom'])
                if artifact_group.get('main'):
                    display_names.append(artifact_group['main'])
                if artifact_group.get('tests'):
                    display_names.append(artifact_group['tests'])

                if not display_names:
                    display_names = [artifact_group.get('base', 'unknown-artifact-group')]

                failed.extend(display_names)

        self._remove_local_artifacts([])

        logger.info(
            'Successfully promoted the following artifacts:\n{0}'.format(
                '\n'.join(success) if success else '(none)'
            )
        )

        if len(failed) > 0:
            logger.error(
                'Failed to promote the following artifacts:\n{0}'.format('\n'.join(failed))
            )
            raise RuntimeError('Artifact promotion failed')

    def _update_pom(self, path, file):
        """
        Remove the RC suffix from Maven versions
        """
        RC = '-RC'
        in_lst = []
        local_file_path = os.path.join(self.staging_directory, path, file)
        with open(local_file_path, 'r+') as fi:
            for line in fi:
                if RC in line:
                    line = line.replace(RC, '')
                in_lst.append(line)
        with open(local_file_path, 'w+') as fo:
            for line in in_lst:
                fo.write(line)

    def _call_artifactory(self, uri, method, **kwargs):
        """
        Convenience method to call Artifactory
        """
        url = '{0}/artifactory/{1}'.format(self.server, uri.lstrip('/'))
        if 'auth' in self.__dict__:
            kwargs['auth'] = HTTPBasicAuth(self.username, self.password)
        func = getattr(requests, method)
        resp = func(url, **kwargs)

        if not resp.ok:
            logger.error('Artifactory response status: %s', resp.status_code)
            logger.error('Artifactory response body: %s', resp.text)

        resp.raise_for_status()
        return resp

    def _list_artifacts(self):
        """
        Find all artifacts in a given repository
        """
        query = {
            "repo": {
                "$eq": self.repository
            },
            "path": {
                "$match": "{0}/{1}/*".format(
                    self.group.replace('.', '/'),
                    self.component)
            },
            "name": {
                "$match": "*{0}*".format(self.version)
            }
        }
        aql = 'items.find({0})' \
              '.include("repo", "path", "name")' \
              '.sort({{"$asc":["name"]}})'.format(json.dumps(query))

        resp = self._call_artifactory('/api/search/aql/',
                                      'post',
                                      data=aql,
                                      headers={'Content-Type': 'text/plain'})
        return resp.json().get('results', [])

    def _download_artifact(self, path, artifact):
        """
        Download an artifact and validate that the sha1 hash matches that of Artifactory
        """
        local_file_path = os.path.join(self.staging_directory, path, artifact)
        if not os.path.isdir(os.path.dirname(local_file_path)):
            os.makedirs(os.path.dirname(local_file_path))
        url = '{0}/{1}/{2}'.format(self.repository, path, artifact)
        resp = self._call_artifactory(url, 'get', stream=True)
        with open(local_file_path, 'wb') as fd:
            for chunk in resp.iter_content(chunk_size=1024):
                if chunk:
                    fd.write(chunk)
        expected = self._call_artifactory('{0}.sha1'.format(url), 'get').text
        actual = self._hash_file(local_file_path)
        if expected != actual:
            logger.error('Download of {0} failed'.format(artifact))
            raise AssertionError('SHA1 of {0} is {1} but expected {2}'.format(local_file_path,
                                                                               actual,
                                                                               expected))

    def __call__(self):
        """
        Look for artifacts in the RC repo for a given module to promote to release status.
        Fail hard on error
        """
        artifacts = self._list_artifacts()

        for artifact in artifacts:
            artifact_name = artifact.get('name')
            artifact_path = artifact.get('path')
            self._download_artifact(artifact_path, artifact_name)
            if artifact_name.endswith('.pom'):
                self._update_pom(artifact_path, artifact_name)

        self._publish_artifacts()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Promote Artifacts In A Given Maven Repository To Release", formatter_class=argparse.RawTextHelpFormatter)
    main_group = parser.add_argument_group('main')
    main_group.add_argument('repository', help='The name of the Maven repository ex. conexus-rc-local')
    main_group.add_argument('group', help='The Maven Group Id ex. gov.gsa.cnxs')
    main_group.add_argument('component', help='The name of the component to consider ex. domain')
    main_group.add_argument('version', help='The version to be considered ex 01.00.000.48')
    main_group.add_argument('--username', dest='username', nargs='?', metavar='Artifactory User Name',
                            help='The name of the user to connect to the Artifactory Server')
    main_group.add_argument('--password', dest='password', nargs='?', metavar='Artifactory User Password',
                            help='The passowrd of the user to connect to the Artifactory Server')
    main_group.add_argument('--server', dest='server', nargs='?', metavar='Artifactory server',
                            const='https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov', default='https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov',
                            help='The location where the artifactory server can be found')
    main_group.add_argument('--release-repo', dest='release_repo', nargs='?', metavar='Artifactory Maven Release Repo',
                            const='conexus-release-local', default='conexus-release-local',
                            help='The Maven Repository to publish release artifacts to')
    main_group.add_argument('--settings-xml', dest='settings_xml', nargs='?', metavar='Maven settings.xml',
                            default=None,
                            help='Path to the Maven settings.xml file to use for deploy:deploy-file')
    main_group.add_argument('--override', action='store_true',
                            help="Define the version to use during promote to override pom file")
    main_group.add_argument('-D', dest='maven_args', nargs='?', action='append',
                            metavar='Optional Maven Deploy Arguments', default=[],
                            help='Any additional arguments to pass to Maven when deploying')
    options = parser.parse_args()
    promote = Promote(**options.__dict__)
    promote()
