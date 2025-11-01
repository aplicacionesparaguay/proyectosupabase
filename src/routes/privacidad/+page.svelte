<!-- src/routes/privacidad/+page.svelte -->
<script>
  // No se necesita lógica adicional por ahora
</script>

<main class="container">
  <h1>Política de Privacidad</h1>
  <section>
    <h2>1. Introducción</h2>
    <p>
      En <strong>Proyectosupabase</strong>, valoramos tu privacidad y nos comprometemos a proteger tus datos personales. Esta Política de Privacidad explica cómo recopilamos, usamos y protegemos tu información cuando utilizas nuestra aplicación.
    </p>

    <h2>2. Información que Recopilamos</h2>
    <p>
      Recopilamos la siguiente información:
    </p>
    <ul>
      <li><strong>Información personal</strong>: Nombre, email, número de teléfono, y otros datos que nos proporciones al registrarte o usar nuestro servicio.</li>
      <li><strong>Datos de uso</strong>: Información sobre cómo interactúas con nuestra aplicación, como páginas visitadas y acciones realizadas.</li>
      <li><strong>Datos técnicos</strong>: Dirección IP, tipo de navegador, dispositivo, y otros datos técnicos recopilados automáticamente.</li>
    </ul>

    <h2>3. Uso de la Información</h2>
    <p>
      Usamos tu información para:
    </p>
    <ul>
      <li>Proveer y mejorar nuestros servicios.</li>
      <li>Personalizar tu experiencia en la aplicación.</li>
      <li>Enviar comunicaciones relacionadas con el servicio, como actualizaciones o notificaciones.</li>
      <li>Cumplir con obligaciones legales.</li>
    </ul>

    <h2>4. Protección de Datos</h2>
    <p>
      Implementamos medidas de seguridad técnicas y organizativas para proteger tu información contra accesos no autorizados, pérdida o alteración. Sin embargo, ningún sistema es completamente infalible, por lo que trabajamos continuamente para mejorar nuestra seguridad.
    </p>

    <h2>5. Compartir tu Información</h2>
    <p>
      No compartimos tu información personal con terceros, salvo:
    </p>
    <ul>
      <li>Con tu consentimiento explícito.</li>
      <li>Para cumplir con requisitos legales o regulatorios.</li>
      <li>Con proveedores de servicios que trabajan en nuestro nombre (por ejemplo, servicios de alojamiento como Vercel o bases de datos como Supabase).</li>
    </ul>

    <h2>6. Tus Derechos</h2>
    <p>
      Dependiendo de tu jurisdicción, puedes tener derecho a:
    </p>
    <ul>
      <li>Acceder a tus datos personales.</li>
      <li>Corregir o eliminar tu información.</li>
      <li>Restringir el procesamiento de tus datos.</li>
      <li>Oponerte al uso de tus datos para ciertos fines.</li>
    </ul>
    <p>
      Para ejercer estos derechos, contáctanos a través de nuestra página de <a href="/contacto">Contacto</a>.
    </p>

    <h2>7. Cambios a esta Política</h2>
    <p>
      Podemos actualizar esta Política de Privacidad periódicamente. Te notificaremos de cambios significativos a través de la aplicación o por email.
    </p>

    <h2>8. Contacto</h2>
    <p>
      Si tienes preguntas sobre esta Política de Privacidad, contáctanos en:
    </p>
    <p>
      Email: <a href="mailto:soporte@proyectosupabase.com">soporte@proyectosupabase.com</a><br />
      Página de contacto: <a href="/contacto">Contacto</a>
    </p>

    <a href="/" class="back-link">Volver al inicio</a>
  </section>
</main>

<style>
  .container {
    max-width: 800px;
    margin: 0 auto;
    padding: 2rem;
    font-family: Arial, sans-serif;
  }
  h1 {
    font-size: 2.5rem;
    color: #333;
    margin-bottom: 1.5rem;
  }
  h2 {
    font-size: 1.5rem;
    color: #444;
    margin-top: 2rem;
    margin-bottom: 1rem;
  }
  p {
    color: #666;
    line-height: 1.6;
    margin-bottom: 1rem;
  }
  ul {
    list-style-type: disc;
    padding-left: 1.5rem;
    margin-bottom: 1rem;
  }
  li {
    color: #666;
    margin-bottom: 0.5rem;
  }
  .back-link {
    display: inline-block;
    margin-top: 2rem;
    color: #007bff;
    text-decoration: none;
    font-weight: 500;
  }
  .back-link:hover {
    text-decoration: underline;
  }
</style>