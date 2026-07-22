#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TPLG_MAGIC 0x41536f43U
#define TPLG_TYPE_GRAPH 4U
#define TPLG_TYPE_WIDGET 5U
#define TPLG_TYPE_MANIFEST 8U
#define TPLG_HEADER_SIZE 36U
#define WIDGET_STRUCT_SIZE 132U
#define GRAPH_ELEMENT_SIZE 132U
#define NAME_SIZE 44U

struct buffer {
	uint8_t *data;
	size_t len;
	size_t cap;
};

static uint32_t get_le32(const uint8_t *p)
{
	return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
	       (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void put_le32(uint8_t *p, uint32_t value)
{
	p[0] = value;
	p[1] = value >> 8;
	p[2] = value >> 16;
	p[3] = value >> 24;
}

static void die(const char *message)
{
	fprintf(stderr, "rewrite-sof-topology: %s\n", message);
	exit(EXIT_FAILURE);
}

static void append(struct buffer *out, const void *data, size_t len)
{
	if (len > SIZE_MAX - out->len)
		die("output size overflow");
	if (out->len + len > out->cap) {
		size_t cap = out->cap ? out->cap : 65536;

		while (cap < out->len + len)
			cap *= 2;
		out->data = realloc(out->data, cap);
		if (!out->data)
			die("out of memory");
		out->cap = cap;
	}
	memcpy(out->data + out->len, data, len);
	out->len += len;
}

static int fixed_string_ok(const uint8_t *p)
{
	size_t i;

	for (i = 0; i < NAME_SIZE; i++) {
		if (p[i] == '\0')
			return i != 0;
		if (p[i] < 0x20 || p[i] > 0x7e)
			return 0;
	}
	return 0;
}

static int widget_start(const uint8_t *p, size_t remaining)
{
	uint32_t id;

	if (remaining < WIDGET_STRUCT_SIZE || get_le32(p) != WIDGET_STRUCT_SIZE)
		return 0;
	id = get_le32(p + 4);
	if (id > 64)
		return 0;
	return fixed_string_ok(p + 8);
}

static int removed_widget(const char *name)
{
	static const char *const names[] = {
		"eqiir.2.1", "eqfir.2.1", "drc.2.1", "eqiir.4.1",
		"tdfb.11.1", "drc.11.1", "eqiir.12.1", "gain.12.1"
	};
	size_t i;

	for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
		if (!strcmp(name, names[i]))
			return 1;
	return 0;
}

static int endpoint_removed(const uint8_t *name)
{
	char value[NAME_SIZE + 1];

	memcpy(value, name, NAME_SIZE);
	value[NAME_SIZE] = '\0';
	return removed_widget(value);
}

static void add_route(struct buffer *payload, const char *sink,
		      const char *source)
{
	uint8_t route[GRAPH_ELEMENT_SIZE] = { 0 };

	if (strlen(sink) >= NAME_SIZE || strlen(source) >= NAME_SIZE)
		die("replacement route name is too long");
	memcpy(route, sink, strlen(sink));
	memcpy(route + 2 * NAME_SIZE, source, strlen(source));
	append(payload, route, sizeof(route));
}

static void rewrite_widgets(const uint8_t *payload, uint32_t payload_size,
			    uint32_t count, struct buffer *result,
			    uint32_t *new_count, unsigned int *removed)
{
	size_t *starts;
	size_t found = 0;
	size_t pos;
	size_t i;

	starts = calloc((size_t)count + 1, sizeof(*starts));
	if (!starts)
		die("out of memory");

	for (pos = 0; pos + WIDGET_STRUCT_SIZE <= payload_size; pos += 4) {
		if (!widget_start(payload + pos, payload_size - pos))
			continue;
		if (found == count)
			die("found more widget boundaries than the block count");
		starts[found++] = pos;
	}
	if (found != count || (count && starts[0] != 0))
		die("widget boundary count does not match the block header");
	starts[count] = payload_size;

	*new_count = 0;
	for (i = 0; i < count; i++) {
		char name[NAME_SIZE + 1];

		memcpy(name, payload + starts[i] + 8, NAME_SIZE);
		name[NAME_SIZE] = '\0';
		if (removed_widget(name)) {
			fprintf(stderr, "remove widget index block: %s\n", name);
			(*removed)++;
			continue;
		}
		append(result, payload + starts[i], starts[i + 1] - starts[i]);
		(*new_count)++;
	}
	free(starts);
}

static void rewrite_graph(const uint8_t *payload, uint32_t payload_size,
			  uint32_t count, uint32_t index,
			  struct buffer *result, uint32_t *new_count,
			  unsigned int *removed, unsigned int *added)
{
	uint32_t i;

	if (payload_size != count * GRAPH_ELEMENT_SIZE)
		die("graph payload size does not match its element count");
	*new_count = 0;
	for (i = 0; i < count; i++) {
		const uint8_t *route = payload + i * GRAPH_ELEMENT_SIZE;

		if (endpoint_removed(route) || endpoint_removed(route + 2 * NAME_SIZE)) {
			(*removed)++;
			continue;
		}
		append(result, route, GRAPH_ELEMENT_SIZE);
		(*new_count)++;
	}

	if (index == 0) {
		add_route(result, "dai-copier.HDA.Analog.playback", "gain.2.1");
		add_route(result, "host-copier.6.capture", "module-copier.12.2");
		(*new_count) += 2;
		*added += 2;
	} else if (index == 4) {
		add_route(result, "module-copier.4.2", "dai-copier.HDA.Analog.capture");
		(*new_count)++;
		(*added)++;
	} else if (index == 12) {
		add_route(result, "module-copier.12.2", "dai-copier.DMIC.dmic01.capture");
		(*new_count)++;
		(*added)++;
	}
}

static uint8_t *read_file(const char *path, size_t *size)
{
	FILE *file = fopen(path, "rb");
	uint8_t *data;
	long length;

	if (!file) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		exit(EXIT_FAILURE);
	}
	if (fseek(file, 0, SEEK_END) || (length = ftell(file)) < 0 ||
	    fseek(file, 0, SEEK_SET))
		die("cannot determine input size");
	data = malloc((size_t)length);
	if (!data)
		die("out of memory");
	if (fread(data, 1, (size_t)length, file) != (size_t)length)
		die("cannot read input");
	if (fclose(file))
		die("cannot close input");
	*size = (size_t)length;
	return data;
}

static void write_file(const char *path, const uint8_t *data, size_t size)
{
	FILE *file = fopen(path, "wb");

	if (!file) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		exit(EXIT_FAILURE);
	}
	if (fwrite(data, 1, size, file) != size || fclose(file))
		die("cannot write output");
}

int main(int argc, char **argv)
{
	uint8_t *input;
	size_t input_size;
	size_t offset = 0;
	struct buffer output = { 0 };
	size_t manifest_offset = SIZE_MAX;
	unsigned int widgets_removed = 0;
	unsigned int routes_removed = 0;
	unsigned int routes_added = 0;

	if (argc != 3) {
		fprintf(stderr, "usage: %s INPUT.tplg OUTPUT.tplg\n", argv[0]);
		return EXIT_FAILURE;
	}
	input = read_file(argv[1], &input_size);

	while (offset < input_size) {
		const uint8_t *header;
		const uint8_t *payload;
		uint32_t header_size, payload_size, type, index, count;
		struct buffer rewritten = { 0 };
		uint32_t new_count;
		size_t output_header_offset;

		if (input_size - offset < TPLG_HEADER_SIZE)
			die("truncated topology header");
		header = input + offset;
		if (get_le32(header) != TPLG_MAGIC)
			die("invalid topology magic");
		type = get_le32(header + 12);
		header_size = get_le32(header + 16);
		payload_size = get_le32(header + 24);
		index = get_le32(header + 28);
		count = get_le32(header + 32);
		if (header_size < TPLG_HEADER_SIZE ||
		    header_size > input_size - offset ||
		    payload_size > input_size - offset - header_size)
			die("invalid topology block size");
		payload = header + header_size;

		if (type == TPLG_TYPE_WIDGET) {
			rewrite_widgets(payload, payload_size, count, &rewritten,
					&new_count, &widgets_removed);
		} else if (type == TPLG_TYPE_GRAPH) {
			rewrite_graph(payload, payload_size, count, index, &rewritten,
				      &new_count, &routes_removed, &routes_added);
		} else {
			append(&rewritten, payload, payload_size);
			new_count = count;
		}

		output_header_offset = output.len;
		append(&output, header, header_size);
		put_le32(output.data + output_header_offset + 24, rewritten.len);
		put_le32(output.data + output_header_offset + 32, new_count);
		if (type == TPLG_TYPE_MANIFEST) {
			if (manifest_offset != SIZE_MAX)
				die("multiple manifest blocks found");
			manifest_offset = output.len;
		}
		append(&output, rewritten.data, rewritten.len);
		free(rewritten.data);
		offset += header_size + payload_size;
	}

	if (widgets_removed != 8 || routes_removed != 12 || routes_added != 4)
		die("unexpected rewrite counts");
	if (manifest_offset == SIZE_MAX || output.len - manifest_offset < 16)
		die("missing or truncated manifest");
	put_le32(output.data + manifest_offset + 8,
		 get_le32(output.data + manifest_offset + 8) - widgets_removed);
	put_le32(output.data + manifest_offset + 12,
		 get_le32(output.data + manifest_offset + 12) - routes_removed + routes_added);

	write_file(argv[2], output.data, output.len);
	fprintf(stderr,
		"wrote %s: removed %u widgets, removed %u routes, added %u routes\n",
		argv[2], widgets_removed, routes_removed, routes_added);
	free(output.data);
	free(input);
	return EXIT_SUCCESS;
}
