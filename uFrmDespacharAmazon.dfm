object FrmDespacharAmazon: TFrmDespacharAmazon
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Despachar Pedido - Amazon'
  ClientHeight = 320
  ClientWidth = 420
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object lblTitulo: TLabel
    Left = 16
    Top = 16
    Width = 388
    Height = 20
    Caption = 'Dados de envio (exigidos pela Amazon)'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -15
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object lblCarrierCode: TLabel
    Left = 16
    Top = 56
    Width = 90
    Height = 15
    Caption = 'Transportadora'
  end
  object lblCarrierName: TLabel
    Left = 16
    Top = 108
    Width = 250
    Height = 15
    Caption = 'Nome da Transportadora (so' + #39' se "Other")'
  end
  object lblTrackingNumber: TLabel
    Left = 16
    Top = 160
    Width = 120
    Height = 15
    Caption = 'C'#243'digo de Rastreio'
  end
  object lblShipDate: TLabel
    Left = 16
    Top = 212
    Width = 100
    Height = 15
    Caption = 'Data de Envio'
  end
  object cbCarrierCode: TComboBox
    Left = 16
    Top = 76
    Width = 388
    Height = 23
    Style = csDropDownList
    TabOrder = 0
    OnChange = cbCarrierCodeChange
  end
  object edtCarrierName: TEdit
    Left = 16
    Top = 128
    Width = 388
    Height = 23
    TabOrder = 1
  end
  object edtTrackingNumber: TEdit
    Left = 16
    Top = 180
    Width = 388
    Height = 23
    TabOrder = 2
  end
  object dtShipDate: TDateTimePicker
    Left = 16
    Top = 232
    Width = 200
    Height = 23
    Date = 45000.000000000000000000
    Time = 0.500000000000000000
    Kind = dtkDateTime
    TabOrder = 3
  end
  object CmdConfirmar: TBitBtn
    Left = 16
    Top = 270
    Width = 180
    Height = 34
    Caption = 'Confirmar Despacho'
    TabOrder = 4
    OnClick = CmdConfirmarClick
  end
  object CmdCancelar: TBitBtn
    Left = 224
    Top = 270
    Width = 180
    Height = 34
    Caption = 'Cancelar'
    ModalResult = 2
    TabOrder = 5
  end
end
