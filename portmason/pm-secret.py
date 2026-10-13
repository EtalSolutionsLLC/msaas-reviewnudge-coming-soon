#!/usr/bin/env python3
"""Provider-neutral secret routing for Portmason."""

from __future__ import annotations

import argparse
import ctypes
import json
import importlib.util
import os
import pathlib
import re
import resource
import sys
import subprocess
from pm_log import log
from pathlib import Path
from types import ModuleType

PROVIDER_RE = re.compile(r"^[a-z][a-z0-9-]*$")
ENV_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")

def harden_process() -> None:
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    try:
        libc = ctypes.CDLL(None)
        libc.prctl(4, 0, 0, 0, 0)  # PR_SET_DUMPABLE
    except (AttributeError, OSError):
        pass


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def split_secret_path(secret_path: str) -> tuple[str, str]:
    if ":" not in secret_path:
        raise ValueError("secret path must use provider:secret")
    provider, secret_ref = secret_path.split(":", 1)
    if not PROVIDER_RE.fullmatch(provider):
        raise ValueError("secret path contains an invalid provider")
    if not secret_ref:
        raise ValueError("secret path contains an empty secret reference")
    return provider, secret_ref


def load_provider(secret_path: str) -> tuple[ModuleType, str]:
    provider, secret_ref = split_secret_path(secret_path)
    share = pathlib.Path(
        os.environ.get("PORTMASON_SHARE", pathlib.Path(__file__).resolve().parent)
    )
    provider_file = share / f"pm-secret-provider-{provider}.py"
    if not provider_file.is_file():
        raise RuntimeError(f"secret provider module is unavailable: {provider}")
    module_name = f"portmason_secret_provider_{provider.replace('-', '_')}"
    spec = importlib.util.spec_from_file_location(module_name, provider_file)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load secret provider module: {provider}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, secret_ref


def provider_function(secret_path: str, function_name: str):
    module, secret_ref = load_provider(secret_path)
    function = getattr(module, function_name, None)
    if not callable(function):
        provider, _ = split_secret_path(secret_path)
        raise RuntimeError(
            f"secret provider {provider} does not implement {function_name}"
        )
    return function, secret_ref

def get_secret(secret_path: str) -> bytearray:
    function, secret_ref = provider_function(secret_path, "get_secret")
    result = function(secret_ref)
    value = result if isinstance(result, bytearray) else bytearray(result)
    if not value:
        raise RuntimeError("secret provider returned an empty value")
    return value


def set_secret(secret_path: str, value: bytearray) -> None:
    if not value:
        raise ValueError("refusing to store an empty secret")
    function, secret_ref = provider_function(secret_path, "set_secret")
    function(secret_ref, value)



def read_stdin() -> bytearray:
    value = bytearray()
    while True:
        chunk = os.read(0, 4096)
        if not chunk:
            return value
        value.extend(chunk)


def write_stdout(value: bytes | bytearray) -> None:
    view = memoryview(value)
    while view:
        written = os.write(1, view)
        view = view[written:]


def run_get(secret_path: str) -> None:
    function, secret_ref = provider_function(secret_path, "get_secret")
    secret = bytearray()
    try:
        result = function(secret_ref)
        secret = result if isinstance(result, bytearray) else bytearray(result)
        if not secret:
            raise RuntimeError("secret provider returned an empty value")
        write_stdout(secret)
    finally:
        wipe(secret)


def run_set(secret_path: str) -> None:
    function, secret_ref = provider_function(secret_path, "set_secret")
    secret = read_stdin()
    try:
        if not secret:
            raise ValueError("refusing to store an empty secret")
        function(secret_ref, secret)
    finally:
        wipe(secret)


def run_check(secret_path: str, operation: str) -> None:
    provider_function(secret_path, f"{operation}_secret")


def run_with_secrets(bindings: list[str], command: list[str]) -> None:
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        raise ValueError("run-with-secrets requires a command")

    environment = os.environ.copy()
    secrets: list[bytearray] = []
    try:
        if "--no-interpolate" not in command:
            for binding in bindings:
                if "|" not in binding:
                    raise ValueError("secret environment binding must use NAME|PATH")
                name, secret_path = binding.split("|", 1)
                if not ENV_NAME_RE.fullmatch(name) or not secret_path:
                    raise ValueError("invalid secret environment binding")
                current = environment.get(name, "")
                if current and current.strip().lower() != "secret":
                    continue
                secret = get_secret(secret_path)
                secrets.append(secret)
                environment[name] = bytes(secret).decode("utf-8")

        os.execvpe(command[0], command, environment)
    finally:
        for secret in secrets:
            wipe(secret)

def sops_environment() -> dict[str, str]:
    """Retain the requested placeholder defaults; explicit settings take priority."""
    environment = os.environ.copy()
	#BEGIN PAIR 20261009
    if not environment.get("SOPS_AGE_RECIPIENTS"):
        environment["SOPS_AGE_RECIPIENTS"] = 'age1zxddpnaexu6uu7tcj9k7rtwkvhfx7en8vsnyax4udmw0v8gxzypqxy309e'
    if not environment.get("SOPS_AGE_KEY"):
        environment["SOPS_AGE_KEY"] = 'AGE-SECRET-KEY-19YG6V5QMVWLDCUZTUDX6PSQR0Q73ANF6Q5EA9CX8V7YXVXA0LAQQ7CFLLG'
	#END PAIR 20261009
	#BEGIN PAIR 20261005
    # if not environment.get("SOPS_AGE_RECIPIENTS"):
    #     environment["SOPS_AGE_RECIPIENTS"] = 'age1j39h394nc4l5cpxjlghfardcnwz44yzhcsskqrjm9wtqg2jpg9tqgvdp4l'
    # if not environment.get("SOPS_AGE_KEY"):
    #     environment["SOPS_AGE_KEY"] = 'AGE-SECRET-KEY-1UNECGAYWD5MKAPXD8G835HS00ACH4WU5XCASWSQW56SW7WXANKPQYT60PA'
	#END PAIR 20261005
	#BEGIN PAIR 20260927
    # if not environment.get("SOPS_AGE_RECIPIENTS"):
    #     environment["SOPS_AGE_RECIPIENTS"] = 'age1ddvumycgvlx3zknx54helghqs89kexyh7kgv2e9j48f3039hc4fscxngn3'
    # if not environment.get("SOPS_AGE_KEY"):
    #     environment["SOPS_AGE_KEY"] = 'AGE-SECRET-KEY-1S2ZY4FQYR2L5NFHNJ0MQSEW552T6N77KEWRN8U5V3KRFY0VV7GWSC3MKR3'
	#END PAIR 20260927

    return environment


def sops_run(arguments: list[str], value: bytes | None = None) -> bytes:
    """One subprocess boundary for SOPS; diagnostics never enter stdout."""
    result = subprocess.run(
        ["sops", *arguments], input=value, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=sops_environment(),
    )
    if result.returncode:
        # Forward SOPS's diagnostic so missing keys and malformed input are actionable.
        sys.stderr.buffer.write(result.stderr)
        raise RuntimeError(f"SOPS {arguments[0]} failed (exit {result.returncode})")
    return result.stdout


def sops_format_args(target: pathlib.Path, *, output: bool = False) -> list[str]:
    """Recognize Portmason dotenv filenames that SOPS cannot infer."""
    name = target.name
    if not (name == ".env" or name.startswith(".env.") or name.endswith(".env")):
        return []
    arguments = ["--input-type", "dotenv"]
    if output:
        arguments.extend(["--output-type", "dotenv"])
    return arguments


def sops_is_encrypted(filename: str) -> bool:
    target = pathlib.Path(filename).resolve()
    if not target.is_file():
        raise ValueError(f"not a file: {filename}")
    status = json.loads(sops_run(["filestatus", *sops_format_args(target), str(target)]))
    if not isinstance(status, dict) or type(status.get("encrypted")) is not bool:
        raise ValueError("unexpected SOPS file status")
    return status["encrypted"]


def sops_transform(filename: str, action: str) -> bytes:
    target = pathlib.Path(filename).resolve()
    encrypted = sops_is_encrypted(str(target))
    if encrypted == (action == "encrypt"):
        return target.read_bytes()
    return sops_run([action, *sops_format_args(target, output=True), str(target)])


def atomic_write(target: pathlib.Path, value: bytes) -> None:
    import tempfile
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix=".pm-sops-")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def sops_file(filename: str, action: str, stdout: bool) -> None:
    target = pathlib.Path(filename).resolve()
    encrypted = sops_is_encrypted(str(target))
    if encrypted == (action == "encrypt"):
        if stdout:
            write_stdout(target.read_bytes())
        return
    output = sops_run([action, *sops_format_args(target, output=True), str(target)])
    if stdout:
        write_stdout(output)
        return
    # Preserve the original in an owner-only backup before replacing it.
    atomic_write(pathlib.Path(str(target) + ".bak"), target.read_bytes())
    atomic_write(target, output)
    print(f"SOPS {action} completed: {filename}", file=sys.stderr)


def sops_decrypt_file(filename):
    return sops_transform(filename, "decrypt").decode("utf-8")


def resolve_env_file(filename):
	"""Resolve dotenv dependencies through the existing secret-provider router."""
	import importlib.machinery
	import shlex
	import uuid
	decrypted_env_file = sops_decrypt_file(filename)

	renderer = importlib.machinery.SourceFileLoader(
		"pm_env_renderer", str(pathlib.Path(__file__).with_name("pm-util-render-env"))
	).load_module()
	definitions = {}
	pending = ""
	for number, line in enumerate(decrypted_env_file.splitlines(), 1):
		if not pending and (not line.strip() or line.lstrip().startswith("#")):
			continue
		pending += ("\n" if pending else "") + line
		match = re.fullmatch(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", pending, re.S)
		if not match:
			raise ValueError(f"unsupported dotenv statement at line {number}")
		key, rhs = match.groups()
		try:
			tokens = shlex.split(rhs, comments=True)
		except ValueError:
			continue
		if len(tokens) > 1 or rhs.strip().startswith("("):
			raise ValueError(f"unsupported dotenv value for {key}")
		definitions[key] = (tokens[0] if tokens else "", rhs.lstrip().startswith("'"))
		pending = ""
		
	if pending:
		raise ValueError("unterminated dotenv value")

	bindings = {}
	""" 	raw_paths = definitions.get("SECRET_PATHS", (os.environ.get("SECRET_PATHS", ""), True))[0]
	for line in raw_paths.splitlines():
		line = line.strip()
		if not line or line.startswith("#"):
			continue
		name, sep, reference = line.partition("|")
		name, reference = name.strip(), reference.strip()
		if not sep or not ENV_NAME_RE.fullmatch(name) or not reference or name in bindings:
			raise ValueError("invalid or duplicate SECRET_PATHS binding")
		if name == "SECRET_PATHS":
			raise ValueError("SECRET_PATHS cannot map itself")
		bindings[name] = referencec """

	native_environment = os.environ
	inherited = dict(native_environment)
	values, active, sensitive = {}, [], set()
	marker = "PM_OPAQUE_" + uuid.uuid4().hex + "_"
	
	def expand(text):
		opaque = {}
		def protect(value):
			if not value:
				return value
			token = marker + str(len(opaque))
			opaque[token] = value
			return token
		class Dependencies(dict):
			def get(self, name, default=None):
				if name not in definitions and name not in bindings and name not in inherited:
					return default
				result = resolve(name)
				if active and name in sensitive:
					sensitive.add(active[-1])
				return protect(result)
		# Never interpret shell execution or rescan substituted values.
		if "$(" in text or "`" in text:
			raise ValueError("command substitution is unsupported in dotenv")
		text = text.replace("\\$", protect("$"))
		result = renderer.render_text(text, Dependencies(), {})
		result = re.sub(re.escape(marker) + r"\d+", lambda m: opaque[m[0]], result)
		return result

	def resolve(key):
		if key in values:
			return values[key]
		if key in active:
			raise ValueError("dotenv dependency cycle: " + " -> ".join(active + [key]))
		active.append(key)
		try:
			if key in bindings:
				sensitive.add(key)
				reference = expand(bindings[key])
				secret = bytearray()
				previous_environment = os.environ
				try:
					os.environ = ProviderEnvironment()
					secret = get_secret(reference)
					value = bytes(secret).decode("utf-8")
				except Exception:
					raise ValueError(f"secret resolution failed for {key}") from None
				finally:
					os.environ = previous_environment
					wipe(secret)
				if not value:
					raise ValueError(f"secret resolution returned an invalid value for {key}")
			else:
				raw, literal = definitions.get(key, (inherited.get(key, ""), True))
				value = raw if literal or key == "SECRET_PATHS" else expand(raw)
			if "\x00" in value:
				raise ValueError(f"NUL is unsupported in {key}")
			values[key] = value
			native_environment[key] = value
			return value
		finally:
			active.pop()

	# Adapter getenv calls join the recursive graph, including provider defaults.
	from collections.abc import MutableMapping
	class ProviderEnvironment(MutableMapping):
		def __getitem__(self, key):
			if key in definitions or key in bindings:
				return resolve(key)
			return native_environment[key]
		def __setitem__(self, key, value):
			native_environment[key] = value
		def __delitem__(self, key):
			del native_environment[key]
		def __iter__(self):
			return iter(native_environment)
		def __len__(self):
			return len(native_environment)

	output_keys = list(dict.fromkeys([*definitions, *bindings]))
	for key in output_keys:
		resolve(key)
	for key in output_keys:
		print("export " + key + "=" + shlex.quote(values[key]))
	print("export __PM_RESOLVED_ENV_KEYS=" + shlex.quote(":".join(output_keys)))
	print("export __PM_RESOLVED_SECRET_KEYS=" + shlex.quote(":".join(sorted(sensitive))))

def encrypt_file(filename, plaintext, file_format="dotenv"):
    """Encrypt in memory; write only ciphertext, replacing atomically."""
    target = pathlib.Path(filename).resolve()
    recipient = sops_environment().get("SOPS_AGE_RECIPIENTS", "").strip()
    if not recipient:
        raise RuntimeError(
            "SOPS_AGE_RECIPIENTS is required to encrypt generated files"
        )

    ciphertext = sops_run(
        [
            "--encrypt", "--config=/dev/null",# f"--age={recipient}",
            f"--input-type={file_format}", f"--output-type={file_format}",
            f"--filename-override={target}", "/dev/stdin",
        ],
        plaintext.encode("utf-8"),
    )
    if not ciphertext.strip():
        raise RuntimeError(f"Encryption returned empty output for {target}")
    atomic_write(target, ciphertext)

def write_resolved_env(filename, public_filename):
	"""Serialize resolved values without another interpolation pass."""
	keys = os.environ.get("__PM_RESOLVED_ENV_KEYS", "").split(":")
	if not any(keys):
		raise RuntimeError("resolved environment keys are missing; run resolve-env before serialization")
	public, lines = {}, []
	for key in filter(None, keys):
		value = os.environ[key]
		lines.append(key + "='" + value + "'\n")
		public[key] = value
	log("Created " + str(len(lines)) + " key-value-pairs to write to disk as '" + filename + "'.")
	log("Created dictionary with " + str(len(public)) + " entries to write to disk as '" + public_filename + "'.")    
	encrypt_file(filename, "".join(lines), "dotenv")
	encrypt_file(public_filename, json.dumps(public, indent=2) + "\n", "json")

def main() -> int:
	parser = argparse.ArgumentParser()
	subparsers = parser.add_subparsers(dest="command", required=True)

	get_parser = subparsers.add_parser("get-secret")
	get_parser.add_argument("secret_path")

	set_parser = subparsers.add_parser("set-secret")
	set_parser.add_argument("secret_path")

	check_parser = subparsers.add_parser("check-secret")
	check_parser.add_argument("operation", choices=("get", "set"))
	check_parser.add_argument("secret_path")

	run_parser = subparsers.add_parser("run-with-secrets")
	run_parser.add_argument("--secret-env", action="append", default=[])
	run_parser.add_argument("command_args", nargs=argparse.REMAINDER)

	resolve_parser = subparsers.add_parser("resolve-env")
	resolve_parser.add_argument("filename")
	write_parser = subparsers.add_parser("write-resolved-env")
	write_parser.add_argument("filename")
	write_parser.add_argument("public_filename")

	encrypt_parser = subparsers.add_parser("encrypt-file")
	encrypt_parser.add_argument("filename")
	encrypt_parser.add_argument("--format", choices=("dotenv", "json"), default="dotenv")

	sops_parser = subparsers.add_parser("sops")
	sops_parser.add_argument("action", choices=("encrypt", "decrypt", "status"))
	sops_parser.add_argument("filename")
	sops_parser.add_argument("--stdout", action="store_true")

	args = parser.parse_args()
	harden_process()

	try:
		if args.command == "sops":
			if args.action == "status":
				encrypted = sops_is_encrypted(args.filename)
				print("SOPS encrypted" if encrypted else "Not SOPS encrypted")
				return 0 if encrypted else 1
			sops_file(args.filename, args.action, args.stdout)
		elif args.command == "encrypt-file":
			encrypt_file(args.filename, sys.stdin.read(), args.format)
		elif args.command == "resolve-env":
			resolve_env_file(args.filename)
		elif args.command == "write-resolved-env":
			write_resolved_env(args.filename, args.public_filename)
		elif args.command == "get-secret":
			run_get(args.secret_path)
		elif args.command == "set-secret":
			run_set(args.secret_path)
		elif args.command == "run-with-secrets":
			run_with_secrets(args.secret_env, args.command_args)
		else:
			run_check(args.secret_path, args.operation)
		return 0
	except Exception as exc:
		print(f"pm-secret.py: {exc}", file=sys.stderr)
		return 2


if __name__ == "__main__":
	raise SystemExit(main())
