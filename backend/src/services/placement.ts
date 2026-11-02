/** Match the floor encoded by a lobby name; room floor is not authoritative. */
export function lobbyFloor(name: string): number | null {
  const leadingChar = name.trim().charAt(0);
  return leadingChar === '1' ? 1 : leadingChar === '2' ? 2 : null;
}
