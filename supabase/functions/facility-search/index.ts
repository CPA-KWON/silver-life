import { createHandler } from './handler.ts';

Deno.serve(createHandler({ env: (key) => Deno.env.get(key), fetch }));
