import type pg from 'pg';

/** Recompute occupancy only; billing and historical stay assignments are untouched. */
export async function refreshRoomOccupancy(client: pg.PoolClient, roomId: string): Promise<void> {
  await client.query(`UPDATE rooms SET
    total_beds = (SELECT count(*) FROM room_beds WHERE room_id=$1),
    occupied_beds = (SELECT count(*) FROM room_beds WHERE room_id=$1 AND status='occupied'),
    current_attendants = COALESCE((SELECT sum(attendant_count) FROM stays WHERE room_id=$1 AND status='active'),0),
    status = CASE WHEN status IN ('maintenance','cleaning','unavailable') THEN status
      WHEN status='pending_discharge' AND EXISTS(SELECT 1 FROM stays WHERE room_id=$1 AND status='active') THEN status
      WHEN NOT EXISTS(SELECT 1 FROM room_beds WHERE room_id=$1) THEN
        CASE WHEN EXISTS(SELECT 1 FROM stays WHERE room_id=$1 AND status='active') THEN 'occupied' ELSE 'available' END
      WHEN NOT EXISTS(SELECT 1 FROM room_beds WHERE room_id=$1 AND status='occupied') THEN 'available'
      WHEN EXISTS(SELECT 1 FROM room_beds WHERE room_id=$1 AND status<>'occupied') THEN 'partially_occupied'
      ELSE 'occupied' END,
    version=version+1, updated_at=CURRENT_TIMESTAMP WHERE id=$1`, [roomId]);
}
