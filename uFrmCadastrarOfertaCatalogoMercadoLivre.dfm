object FrmCadastrarOfertaCatalogoMercadoLivre: TFrmCadastrarOfertaCatalogoMercadoLivre
  Left = 0
  Top = 0
  Caption = 'Incluir Oferta em Produto do Catalogo - Mercado Livre'
  ClientHeight = 620
  ClientWidth = 620
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 620
    Height = 50
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object lblTitulo: TLabel
      Left = 16
      Top = 12
      Width = 420
      Height = 21
      Caption = 'Incluir Oferta em Produto do Catalogo - Mercado Livre'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object lblBuscaCatalogo: TLabel
    Left = 16
    Top = 62
    Width = 440
    Height = 15
    Caption = 'Produto (marca + modelo) para buscar no catalogo do ML:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object edtBuscaCatalogo: TEdit
    Left = 16
    Top = 82
    Width = 440
    Height = 23
    TabOrder = 1
  end
  object CmdBuscarCatalogo: TBitBtn
    Left = 464
    Top = 81
    Width = 140
    Height = 27
    Caption = 'Buscar no Catalogo'
    TabOrder = 2
    OnClick = CmdBuscarCatalogoClick
  end
  object lstProdutos: TListBox
    Left = 16
    Top = 115
    Width = 588
    Height = 240
    ItemHeight = 15
    TabOrder = 3
  end
  object CmdProximoPasso1: TBitBtn
    Left = 16
    Top = 363
    Width = 140
    Height = 27
    Caption = 'Continuar >>'
    TabOrder = 4
    OnClick = CmdProximoPasso1Click
  end
  object lblProdutoSelecionado: TLabel
    Left = 16
    Top = 62
    Width = 588
    Height = 30
    AutoSize = False
    Caption = 'Produto:'
    WordWrap = True
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object lblSku: TLabel
    Left = 16
    Top = 100
    Width = 120
    Height = 15
    Caption = 'SKU (seu codigo):'
  end
  object edtSku: TEdit
    Left = 16
    Top = 118
    Width = 270
    Height = 23
    TabOrder = 5
  end
  object lblGarantia: TLabel
    Left = 300
    Top = 100
    Width = 140
    Height = 15
    Caption = 'Garantia:'
  end
  object edtGarantia: TEdit
    Left = 300
    Top = 118
    Width = 304
    Height = 23
    TabOrder = 6
  end
  object lblCondicao: TLabel
    Left = 16
    Top = 148
    Width = 120
    Height = 15
    Caption = 'Condicao:'
  end
  object cbCondicao: TComboBox
    Left = 16
    Top = 166
    Width = 136
    Height = 23
    Style = csDropDownList
    TabOrder = 7
  end
  object lblTipoAnuncio: TLabel
    Left = 160
    Top = 148
    Width = 140
    Height = 15
    Caption = 'Tipo de anuncio:'
  end
  object cbTipoAnuncio: TComboBox
    Left = 160
    Top = 166
    Width = 168
    Height = 23
    Style = csDropDownList
    TabOrder = 8
  end
  object lblPreco: TLabel
    Left = 16
    Top = 196
    Width = 120
    Height = 15
    Caption = 'Preco (R$):'
  end
  object edtPreco: TEdit
    Left = 16
    Top = 214
    Width = 136
    Height = 23
    TabOrder = 9
  end
  object lblEstoque: TLabel
    Left = 160
    Top = 196
    Width = 120
    Height = 15
    Caption = 'Estoque:'
  end
  object edtEstoque: TEdit
    Left = 160
    Top = 214
    Width = 168
    Height = 23
    TabOrder = 10
  end
  object CmdVerFichaProduto: TBitBtn
    Left = 336
    Top = 213
    Width = 268
    Height = 27
    Caption = 'Ver Ficha do Produto do Catalogo'
    TabOrder = 11
    OnClick = CmdVerFichaProdutoClick
  end
  object CmdVoltar: TBitBtn
    Left = 16
    Top = 258
    Width = 120
    Height = 27
    Caption = '<< Voltar'
    TabOrder = 12
    OnClick = CmdVoltarClick
  end
  object CmdPublicar: TBitBtn
    Left = 144
    Top = 258
    Width = 180
    Height = 27
    Caption = 'Publicar Oferta'
    TabOrder = 13
    OnClick = CmdPublicarClick
  end
  object CmdFechar: TBitBtn
    Left = 484
    Top = 400
    Width = 120
    Height = 27
    Caption = 'Fechar'
    TabOrder = 14
    OnClick = CmdFecharClick
  end
  object MemoLog: TMemo
    Left = 16
    Top = 434
    Width = 588
    Height = 170
    ScrollBars = ssVertical
    TabOrder = 15
    ReadOnly = True
  end
end
