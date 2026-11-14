package weights60

import (
	"bytes"
	"encoding/json"
	"fmt"
)

// A JSON object read from a file with its keys kept in order and its values left as written, so a file can
// be extended without changing what it already holds.
type ordered struct {
	keys   []string
	values map[string]json.RawMessage
}

func parseOrdered(data []byte) (*ordered, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	token, err := decoder.Token()
	if err != nil {
		return nil, err
	}
	if delim, ok := token.(json.Delim); !ok || delim != '{' {
		return nil, fmt.Errorf("not a JSON object")
	}
	o := &ordered{values: map[string]json.RawMessage{}}
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		key, ok := token.(string)
		if !ok {
			return nil, fmt.Errorf("a key that is not a string")
		}
		var raw json.RawMessage
		if err := decoder.Decode(&raw); err != nil {
			return nil, err
		}
		if _, seen := o.values[key]; !seen {
			o.keys = append(o.keys, key)
		}
		o.values[key] = raw
	}
	return o, nil
}

func (o *ordered) get(key string) json.RawMessage { return o.values[key] }

func (o *ordered) object(key string) (*ordered, error) {
	raw, ok := o.values[key]
	if !ok {
		return nil, fmt.Errorf("no %q", key)
	}
	return parseOrdered(raw)
}

func (o *ordered) set(key string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if _, seen := o.values[key]; !seen {
		o.keys = append(o.keys, key)
	}
	o.values[key] = data
	return nil
}

func (o *ordered) remove(key string) {
	if _, seen := o.values[key]; !seen {
		return
	}
	delete(o.values, key)
	for i, k := range o.keys {
		if k == key {
			o.keys = append(o.keys[:i], o.keys[i+1:]...)
			break
		}
	}
}

func (o *ordered) MarshalJSON() ([]byte, error) {
	var b bytes.Buffer
	b.WriteByte('{')
	for i, key := range o.keys {
		if i > 0 {
			b.WriteByte(',')
		}
		name, err := json.Marshal(key)
		if err != nil {
			return nil, err
		}
		b.Write(name)
		b.WriteByte(':')
		b.Write(o.values[key])
	}
	b.WriteByte('}')
	return b.Bytes(), nil
}
