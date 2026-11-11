'use client';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

export type DatoGrafico = { dia: string; asistio: number; tardanza: number; permiso: number; falta: number };

const SERIES = [
  { clave: 'asistio', nombre: 'Asistió', color: 'var(--ok)' },
  { clave: 'tardanza', nombre: 'Tardanza', color: 'var(--alerta)' },
  { clave: 'permiso', nombre: 'Permiso', color: 'var(--info)' },
  { clave: 'falta', nombre: 'Falta', color: 'var(--peligro)' },
] as const;

/** Barras apiladas por día: cuántos trabajadores asistieron, llegaron tarde, tuvieron permiso o faltaron. */
export function GraficoDias({ datos, total }: { datos: DatoGrafico[]; total: number }) {
  return (
    <div className="h-56 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={datos} margin={{ top: 4, right: 4, bottom: 0, left: -24 }} barCategoryGap="28%">
          <CartesianGrid vertical={false} stroke="var(--linea)" strokeDasharray="3 3" />
          <XAxis dataKey="dia" tick={{ fill: 'var(--tenue)', fontSize: 11 }} axisLine={{ stroke: 'var(--linea)' }} tickLine={false} />
          <YAxis allowDecimals={false} domain={[0, Math.max(total, 1)]} tick={{ fill: 'var(--tenue)', fontSize: 11 }} axisLine={false} tickLine={false} />
          <Tooltip
            cursor={{ fill: 'var(--hundido)' }}
            contentStyle={{ background: 'var(--superficie)', border: '1px solid var(--linea)', borderRadius: 8, fontSize: 12, color: 'var(--tinta)' }}
            labelStyle={{ color: 'var(--tinta)', fontWeight: 600 }}
          />
          {SERIES.map((s, i) => (
            <Bar key={s.clave} dataKey={s.clave} name={s.nombre} stackId="dias" fill={s.color} radius={i === SERIES.length - 1 ? [4, 4, 0, 0] : 0} />
          ))}
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
