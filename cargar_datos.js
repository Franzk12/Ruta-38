// ════════════════════════════════════════════════════════════════════
// SCRIPT PARA CARGAR CATEGORÍAS Y MARCAS/MODELOS EN SUPABASE
// Pega esto en la consola del navegador (F12 > Console) con la app abierta
// ════════════════════════════════════════════════════════════════════

const categoriasData = [
  'Motor', 'Transmisión', 'Sistema de Frenos', 'Suspensión', 'Dirección',
  'Sistema Eléctrico', 'Iluminación', 'Carrocería', 'Interior', 'Vidrios',
  'Espejos', 'Cerraduras', 'Cinturones', 'Airbags', 'Tablero',
  'Manija de Puerta', 'Bisagra', 'Moldura', 'Parachoques', 'Capó',
  'Maletero', 'Puertas', 'Ventanas', 'Techo', 'Asientos',
  'Alfombra', 'Tapicería', 'Volante', 'Cambios', 'Frenos',
  'Discos de Freno', 'Pastillas de Freno', 'Tambor de Freno', 'Cilindro Maestro', 'Manguera Freno',
  'Correa de Distribución', 'Tensor Correa', 'Manguera de Radiador', 'Termostato', 'Bomba de Agua',
  'Radiador', 'Alternador', 'Motor de Arranque', 'Batería', 'Cables Batería',
  'Bobina de Encendido', 'Bujías', 'Distribuidor', 'Rotor', 'Condensador',
  'Filtro de Aire', 'Filtro de Aceite', 'Filtro Combustible', 'Filtro Habitáculo', 'Inyector',
  'Carburador', 'Bomba de Combustible', 'Tanque Combustible', 'Manguera Combustible', 'Tubo Escape',
  'Silenciador', 'Catalizador', 'Sensor de Oxígeno', 'MAF', 'Sensor Temperatura',
  'Válvula EGR', 'Culata', 'Bloque Motor', 'Pistones', 'Bielas',
  'Cigüeñal', 'Árbol de Levas', 'Válvulas', 'Guías Válvulas', 'Asientos Válvulas',
  'Resortes Válvulas', 'Cadena Distribución', 'Rodamientos', 'Retenes', 'Empaques',
  'Juntas', 'Aceite Motor', 'Refrigerante', 'Líquido Frenos', 'Líquido Dirección',
  'Refrigerante Aire Acondicionado', 'Parabrisas', 'Faros', 'Luces', 'Intermitentes'
];

const marcasData = [
  'Toyota|Corolla,Camry,Hilux,Fortuner,RAV4,Yaris,Avanza,Etios,Hiace,Land Cruiser,Prius,Vios,4Runner,Sequoia,Tundra,Tacoma',
  'Ford|Fiesta,Focus,Mondeo,Ranger,F-150,Escape,Edge,Explorer,Expedition,Mustang,Fusion,Escort',
  'Chevrolet|Cruze,Spark,Onix,Aveo,Optra,Captiva,Equinox,Tahoe,Suburban,Trailblazer,Colorado',
  'Volkswagen|Gol,Polo,Golf,Jetta,Passat,Tiguan,Touareg,Bora,Virtus,Voyage',
  'Honda|Civic,Accord,CR-V,Pilot,Fit,HR-V,Odyssey,Ridgeline,City,Brio',
  'Hyundai|Elantra,Sonata,Santa Fe,Tucson,i10,i20,Venue,Accent,Kona,Ioniq',
  'Kia|Cerato,Sportage,Sorento,Forte,Rio,Picanto,Seltos,Stinger',
  'Renault|Duster,Sandero,Logan,Kwid,Koleos,Fluence,Scenic',
  'Peugeot|307,308,3008,5008,208,207,206,301,2008',
  'Citroën|C3,C4,C5,Aircross,C1,Berlingo',
  'Fiat|Uno,Palio,Argo,Cronos,Toro,500,Panda',
  'Nissan|Versa,Altima,Frontier,Pathfinder,Murano,Rogue,Qashqai,March,Sentra',
  'Mazda|3,6,CX-5,CX-3,MX-5,Tribute,Premacy',
  'Suzuki|Swift,Vitara,Ignis,Ertiga,Wagon R,Alto,S-Cross',
  'Mitsubishi|Lancer,Outlander,Pajero,Mirage,ASX,Eclipse',
  'Isuzu|D-Max,MU-X,Rodeo',
  'BMW|320,330,520,530,X3,X5,X1,Z4,M3,M5',
  'Mercedes-Benz|C-Class,E-Class,S-Class,A-Class,GLA,GLC,GLE,GL,Sprinter',
  'Audi|A3,A4,A6,A8,Q3,Q5,Q7,TT,RS',
  'Volkswagen|Golf,Jetta,Passat,Tiguan,Touareg,Beetle,Bora,Polo,Gol',
  'Volvo|S40,S60,S80,S90,XC60,XC90,XC40',
  'Jeep|Wrangler,Cherokee,Compass,Renegade,Patriot,Grand Cherokee',
  'Dodge|Durango,Journey,Charger,Challenger,Ram',
  'Chrysler|300,Pacifica,Sebring',
  'Subaru|Legacy,Outback,Impreza,WRX,Forester,XV',
  'Saab|9000,900,9-5,9-3',
  'SEAT|Leon,Ibiza,Toledo,Altea,Tarraco',
  'Skoda|Octavia,Fabia,Superb,Yeti,Karoq',
  'Lada|Niva,Priora,Granta,Vesta',
  'Daewoo|Nubira,Lacetti,Matiz,Tico',
  'Geely|Emgrand,CK,GC6,Kingkong',
  'Chery|Tiggo,QQ,A3,Fulwin',
  'Great Wall|Hover,Wey,Tank',
  'BYD|Qin,Song,Yuan,F3,F6,F7',
  'Haval|H6,H9,H2,H5'
];

async function cargarDatos() {
  console.log('🚀 Iniciando carga de datos...');
  let catCount = 0;
  let marcasCount = 0;

  // ════════════════════════════════════════════════════════════════════
  // 1. CARGAR CATEGORÍAS
  // ════════════════════════════════════════════════════════════════════
  console.log('📦 Cargando categorías...');
  
  for (let cat of categoriasData) {
    try {
      // Verificar si ya existe
      const existe = await sbGet('categorias', `nombre=eq.${encodeURIComponent(cat)}`);
      if (existe && existe.length > 0) {
        console.log(`⏭️  ${cat} ya existe`);
        catCount++;
        continue;
      }

      // Crear nueva categoría
      const res = await sbPost('categorias', {
        nombre: cat,
        activa: true
      });
      catCount++;
      console.log(`✓ ${cat}`);
    } catch (err) {
      console.error(`✗ Error al cargar ${cat}:`, err.message);
    }
  }

  console.log(`\n✅ Categorías cargadas: ${catCount}/${categoriasData.length}`);

  // ════════════════════════════════════════════════════════════════════
  // 2. CARGAR MARCAS Y MODELOS
  // ════════════════════════════════════════════════════════════════════
  console.log('\n🏎️  Cargando marcas y modelos...');
  
  for (let marcaStr of marcasData) {
    const [nombre, modelos] = marcaStr.split('|');
    const modelosList = modelos ? modelos.split(',').map(m => m.trim()) : [];
    
    try {
      // Verificar si la marca ya existe
      const existe = await sbGet('marcas', `nombre=eq.${encodeURIComponent(nombre)}`);
      if (existe && existe.length > 0) {
        console.log(`⏭️  ${nombre} ya existe`);
        marcasCount++;
        continue;
      }

      // Crear marca con modelos
      const marcaConModelos = nombre + (modelosList.length > 0 ? '|' + modelosList.join('|') : '');
      const res = await sbPost('marcas', {
        nombre: marcaConModelos,
        activa: true
      });
      marcasCount++;
      console.log(`✓ ${nombre} (${modelosList.length} modelos)`);
    } catch (err) {
      console.error(`✗ Error al cargar ${nombre}:`, err.message);
    }
  }

  console.log(`\n✅ Marcas cargadas: ${marcasCount}/${marcasData.length}`);
  
  // ════════════════════════════════════════════════════════════════════
  // FINALIZACIÓN
  // ════════════════════════════════════════════════════════════════════
  console.log('\n' + '═'.repeat(60));
  console.log('✅ CARGA COMPLETADA EXITOSAMENTE');
  console.log('═'.repeat(60));
  console.log(`Total Categorías: ${catCount}`);
  console.log(`Total Marcas: ${marcasCount}`);
  console.log('\n⚡ Recargando página...');
  
  setTimeout(function() {
    location.reload();
  }, 2000);
}

// ════════════════════════════════════════════════════════════════════
// EJECUTAR
// ════════════════════════════════════════════════════════════════════
console.log('%c🔄 CARGADOR DE DATOS REPUESTO POS', 'color: #f97316; font-size: 16px; font-weight: bold;');
console.log('Iniciando en 3 segundos...\n');

setTimeout(cargarDatos, 3000);
