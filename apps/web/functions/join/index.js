import { onRequestGet as renderInvitation } from "./[token].js";

export function onRequestGet({ request }) {
  return renderInvitation({ request, params: { token: "" } });
}
