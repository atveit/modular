#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

extern int64_t mojo_ios_file_roundtrip(const int8_t *path);
extern int64_t mojo_ios_environment_roundtrip(void);
extern int64_t mojo_ios_serial_stdlib_roundtrip(void);

int main(void) {
  const char *temporary_directory = getenv("TMPDIR");
  if (!temporary_directory)
    return 10;
  if (mojo_ios_serial_stdlib_roundtrip() != 0)
    return 17;
  if (mojo_ios_environment_roundtrip() != 0)
    return 16;

  char path[1024];
  int path_length =
      snprintf(path, sizeof(path), "%s/mojo-dir-%ld/nested/payload.txt",
               temporary_directory, (long)getpid());
  if (path_length < 0 || (size_t)path_length >= sizeof(path))
    return 11;

  unlink(path);
  if (mojo_ios_file_roundtrip((const int8_t *)path) != 0)
    return 12;

  FILE *file = fopen(path, "rb");
  if (!file)
    return 13;
  char contents[64] = {0};
  size_t bytes_read = fread(contents, 1, sizeof(contents) - 1, file);
  int close_result = fclose(file);
  int remove_result = unlink(path);
  char nested_directory[1024];
  char root_directory[1024];
  int nested_length =
      snprintf(nested_directory, sizeof(nested_directory),
               "%s/mojo-dir-%ld/nested", temporary_directory, (long)getpid());
  int root_length =
      snprintf(root_directory, sizeof(root_directory), "%s/mojo-dir-%ld",
               temporary_directory, (long)getpid());
  if (nested_length < 0 || (size_t)nested_length >= sizeof(nested_directory) ||
      root_length < 0 || (size_t)root_length >= sizeof(root_directory))
    return 18;
  int remove_nested_result = rmdir(nested_directory);
  int remove_root_result = rmdir(root_directory);
  if (close_result != 0 || remove_result != 0 || remove_nested_result != 0 ||
      remove_root_result != 0)
    return 14;
  if (bytes_read != strlen("Hello from a Mojo iOS file.") ||
      strcmp(contents, "Hello from a Mojo iOS file.") != 0)
    return 15;

  puts("MOJO_COMPILERRT_FILE_ROUNDTRIP_PASS");
  return 0;
}
